/**
 * QuotaDO atomic-counter tests. Drives the real QuotaDO with an in-memory
 * storage + a blockConcurrencyWhile that actually serializes callbacks, so the
 * test exercises the same check-and-set path the Worker uses. Proves the two
 * HIGH findings are closed: /issue can't over-mint and /credit can't double-credit
 * even under a concurrent burst.
 */
import { QuotaDO } from '../src/quotado.ts';

function makeDO() {
  const map = new Map();
  let chain = Promise.resolve();
  const state = {
    storage: {
      async get(k) { return map.get(k); },
      async put(k, v) { map.set(k, v); },
      async delete(k) { return map.delete(k); },
      async deleteAll() { map.clear(); },
      async setAlarm() {},
    },
    // Serialize like a real DO: each callback runs to completion before the next.
    blockConcurrencyWhile(cb) {
      const run = chain.then(() => cb());
      chain = run.catch(() => {});
      return run;
    },
  };
  return new QuotaDO(state);
}

function post(dobj, path, body) {
  return dobj.fetch(new Request(`https://do${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  })).then((r) => r.json());
}

let failed = 0;
function assert(cond, msg) {
  if (cond) console.log(`PASS: ${msg}`);
  else { console.error(`FAIL: ${msg}`); failed++; }
}

// ---- /reserve never exceeds max, even under a concurrent burst -------------
{
  const d = makeDO();
  const N = 50, MAX = 10;
  const results = await Promise.all(
    Array.from({ length: N }, () => post(d, '/reserve', { max: MAX, want: 1 }))
  );
  const granted = results.reduce((s, r) => s + r.granted, 0);
  assert(granted === MAX, `reserve burst: ${granted} granted, cap ${MAX} (no over-grant)`);
}

// ---- /reserve with want>1 grants only up to remaining ----------------------
{
  const d = makeDO();
  const a = await post(d, '/reserve', { max: 100, want: 64 });
  const b = await post(d, '/reserve', { max: 100, want: 64 });
  assert(a.granted === 64 && b.granted === 36, `reserveN respects budget: ${a.granted}+${b.granted}=100`);
  const c = await post(d, '/reserve', { max: 100, want: 10 });
  assert(c.granted === 0, 'reserveN grants 0 when exhausted');
}

// ---- /claim is one-time under a concurrent burst (credit dedup) ------------
{
  const d = makeDO();
  const results = await Promise.all(
    Array.from({ length: 25 }, () => post(d, '/claim', {}))
  );
  const wins = results.filter((r) => r.ok).length;
  assert(wins === 1, `claim burst: exactly 1 winner (${wins}) — no double-credit`);
}

// ---- add / spend accounting ------------------------------------------------
{
  const d = makeDO();
  await post(d, '/add', { amount: 100 });
  const balAfterAdd = await post(d, '/get', {});
  assert(balAfterAdd.value === 100, 'add sets balance to 100');
  const spends = await Promise.all(
    Array.from({ length: 130 }, () => post(d, '/spend', {}))
  );
  const ok = spends.filter((r) => r.ok).length;
  assert(ok === 100, `spend burst: exactly 100 succeed against balance 100 (${ok})`);
  const bal = await post(d, '/get', {});
  assert(bal.value === 0, 'balance floored at 0 after over-spend');
}

// ---- refund floors at 0 ----------------------------------------------------
{
  const d = makeDO();
  await post(d, '/reserve', { max: 5, want: 3 });
  await post(d, '/refund', {});
  await post(d, '/refund', {});
  await post(d, '/refund', {});
  await post(d, '/refund', {});
  const bal = await post(d, '/get', {});
  assert(bal.value === 0, 'refund floors at 0');
}

if (failed) { console.error(`\n${failed} TEST(S) FAILED`); process.exit(1); }
console.log('\nALL QUOTA-DO TESTS PASSED');
