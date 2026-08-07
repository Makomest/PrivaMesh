/**
 * SpentTokenDO — strongly-consistent single-spend for anonymous blind tokens.
 *
 * The token /send path used a KV `spent:<nonce>` check-then-set, but KV is
 * eventually consistent: two concurrent spends of ONE token can both read "not
 * spent" and both get co-signed, double-charging the treasury. A Durable Object
 * gives serialized, strongly-consistent storage, so a token can be spent exactly
 * once even under a concurrent race.
 *
 * Sharding: the caller derives the DO id from the token nonce
 * (`idFromName(nonce)`), so each token maps to its OWN DO instance. Distinct
 * tokens hit distinct DOs (full parallelism); the same token always hits the same
 * DO (serialized → single-spend).
 *
 * Protocol (all atomic via blockConcurrencyWhile — no interleaving mid-op):
 *   /claim   reserve the token BEFORE submitting the tx. Fails if already spent
 *            or a fresh claim is in flight. A stale claim (older than CLAIM_TTL,
 *            i.e. a crashed request that never committed/released) is reclaimable.
 *   /commit  finalize as permanently spent after the tx lands. Schedules self-
 *            cleanup so per-token storage doesn't grow forever.
 *   /release undo a claim when the submit failed, so the paid token stays usable.
 */

/** A claim is reclaimable this long after it was made if never committed —
 *  covers a request that crashed between /claim and /commit|/release. */
export const CLAIM_TTL_MS = 60_000;

/** Keep a spent record this long before self-deleting (must exceed the client
 *  token lifetime; matches the old KV `spent:` TTL). */
const SPENT_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;

export type ClaimState = 'spent' | number | undefined; // 'spent' | pendingSince | none
export type ClaimResult = 'ok' | 'spent' | 'pending';

/** Pure decision for /claim, extracted for unit testing. Given the stored state
 *  and now, decide the outcome and the next state to persist (null = no write). */
export function decideClaim(current: ClaimState, now: number, ttl = CLAIM_TTL_MS):
    { result: ClaimResult; next: number | null } {
  if (current === 'spent') return { result: 'spent', next: null };
  if (typeof current === 'number' && now - current < ttl) {
    return { result: 'pending', next: null };   // a fresh claim is in flight
  }
  return { result: 'ok', next: now };            // free, or a stale claim to take over
}

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

const KEY = 's';

export class SpentTokenDO {
  constructor(private state: DOState) {}

  async fetch(req: Request): Promise<Response> {
    const path = new URL(req.url).pathname;
    // blockConcurrencyWhile serializes: while the callback runs no other request
    // is delivered to this object, so check-and-set is atomic.
    const body = await this.state.blockConcurrencyWhile(async () => {
      const cur = (await this.state.storage.get(KEY)) as ClaimState;
      const now = Date.now();

      if (path === '/claim') {
        const { result, next } = decideClaim(cur, now);
        if (next !== null) await this.state.storage.put(KEY, next);
        return { result };
      }
      if (path === '/commit') {
        await this.state.storage.put(KEY, 'spent');
        await this.state.storage.setAlarm(now + SPENT_RETENTION_MS);
        return { result: 'ok' as ClaimResult };
      }
      if (path === '/release') {
        // Only clear a pending claim; never un-spend a committed token.
        if (cur !== 'spent') await this.state.storage.delete(KEY);
        return { result: 'ok' as ClaimResult };
      }
      return { result: 'error' as const };
    });

    const status = body.result === 'ok' ? 200
      : body.result === 'spent' || body.result === 'pending' ? 409 : 404;
    return new Response(JSON.stringify(body), {
      status, headers: { 'content-type': 'application/json' },
    });
  }

  /** Self-cleanup: drop the spent record once it can no longer be replayed. */
  async alarm(): Promise<void> {
    await this.state.storage.deleteAll();
  }
}
