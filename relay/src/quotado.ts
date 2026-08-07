/**
 * QuotaDO — strongly-consistent atomic counters for the money-critical paths.
 *
 * Cloudflare KV is eventually consistent and has no compare-and-set: a
 * `get`-then-`put` counter can be raced by concurrent requests that all read the
 * same stale value and all act on it. That is fine for a UX mirror, but NOT for
 * the counters that gate treasury spend — issuance budget, pack credit dedup,
 * per-account quota, and the daily circuit-breaker. A raced counter there means
 * over-issued tokens, double-credited packs, or a blown daily cap.
 *
 * SpentTokenDO already solved exactly this for single-spend. QuotaDO generalises
 * it: each logical counter key maps to its OWN Durable Object instance
 * (`idFromName(key)`), and every mutation runs inside `blockConcurrencyWhile`, so
 * check-and-set is serialized and strongly consistent. Distinct keys hit distinct
 * DOs (full parallelism); the same key always hits the same DO (no race).
 *
 * Ops (POST, JSON body):
 *   /reserve   { max, want?, ttlMs? } → { granted } — atomically grant up to
 *              `want` (default 1) units without exceeding `max`. granted may be 0.
 *   /refund    { by?, ttlMs? }        → { value }   — decrement (floored at 0).
 *   /add       { amount, ttlMs? }     → { value }   — unconditional add.
 *   /spend     { ttlMs? }             → { ok }       — decrement by 1 iff value>0.
 *   /get                              → { value }
 *   /claim     { ttlMs? }             → { ok }       — one-time flag; ok only the
 *              first time (idempotent dedup, e.g. an Apple transactionId).
 *
 * ttlMs, when given on a mutating op, schedules a self-delete alarm that far in
 * the future so per-key storage doesn't grow forever. It is set once (the first
 * mutation) and never pulled earlier, so a long-lived monthly/daily key survives
 * its whole active window. Omit ttlMs (or 0) to persist indefinitely (pack
 * balances, which represent purchased goods).
 */

const VAL = 'v';        // numeric counter
const CLAIMED = 'c';     // one-time claim flag
const ALARM_SET = 'a';   // whether a cleanup alarm was already scheduled

interface DOState {
  storage: {
    get(key: string): Promise<unknown>;
    put(key: string, value: unknown): Promise<void>;
    delete(key: string): Promise<boolean>;
    deleteAll(): Promise<void>;
    setAlarm(time: number): Promise<void>;
  };
  blockConcurrencyWhile<T>(cb: () => Promise<T>): Promise<T>;
}

export class QuotaDO {
  constructor(private state: DOState) {}

  private async maybeAlarm(ttlMs: unknown): Promise<void> {
    const ttl = Number(ttlMs) || 0;
    if (ttl <= 0) return;
    if (await this.state.storage.get(ALARM_SET)) return;
    await this.state.storage.put(ALARM_SET, 1);
    await this.state.storage.setAlarm(Date.now() + ttl);
  }

  async fetch(req: Request): Promise<Response> {
    const path = new URL(req.url).pathname;
    let body: any = {};
    if (req.method === 'POST') {
      try { body = await req.json(); } catch { body = {}; }
    }

    const out = await this.state.blockConcurrencyWhile(async () => {
      const cur = Number((await this.state.storage.get(VAL)) ?? 0);

      if (path === '/reserve') {
        const max = Number(body.max) || 0;
        const want = Math.max(1, Number(body.want) || 1);
        const granted = Math.max(0, Math.min(want, max - cur));
        if (granted > 0) {
          await this.state.storage.put(VAL, cur + granted);
          await this.maybeAlarm(body.ttlMs);
        }
        return { granted };
      }
      if (path === '/refund') {
        const by = Math.max(1, Number(body.by) || 1);
        const next = Math.max(0, cur - by);
        await this.state.storage.put(VAL, next);
        return { value: next };
      }
      if (path === '/add') {
        const amount = Number(body.amount) || 0;
        const next = cur + amount;
        await this.state.storage.put(VAL, next);
        await this.maybeAlarm(body.ttlMs);
        return { value: next };
      }
      if (path === '/spend') {
        if (cur > 0) {
          await this.state.storage.put(VAL, cur - 1);
          return { ok: true, value: cur - 1 };
        }
        return { ok: false, value: cur };
      }
      if (path === '/get') {
        return { value: cur };
      }
      if (path === '/claim') {
        if (await this.state.storage.get(CLAIMED)) return { ok: false };
        await this.state.storage.put(CLAIMED, 1);
        await this.maybeAlarm(body.ttlMs);
        return { ok: true };
      }
      return { error: 'unknown op' };
    });

    return new Response(JSON.stringify(out), {
      status: 'error' in out ? 404 : 200,
      headers: { 'content-type': 'application/json' },
    });
  }

  /** Self-cleanup once the key can no longer be relevant. */
  async alarm(): Promise<void> {
    await this.state.storage.deleteAll();
  }
}
