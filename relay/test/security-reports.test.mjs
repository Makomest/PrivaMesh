/**
 * Regressions for the reports from Mudit (mudit.raj32@gmail.com), 25 Aug 2026.
 * Run: npx tsx test/security-reports.test.mjs   (from relay/)
 *
 * Three of the six reports were about this Worker:
 *
 *   - a caller could choose the priority fee the treasury pays,
 *   - one blind token could be spent once per spelling of its nonce,
 *   - one subscription could get a fresh monthly allowance per `account` value.
 *
 * Each test below fails against the code as it was.
 */
import assert from 'node:assert';
import { Keypair, Transaction, PublicKey, ComputeBudgetProgram, SystemProgram } from '@solana/web3.js';
import { canonicalNonce, bytesToB64u, b64uToBytes } from '../src/blindtokens.ts';
import { __testing } from '../src/index.ts';
import { SpentTokenDO } from '../src/spenttokens.ts';

const { assertTreasuryOnlyPaysFees, quotaKeyFor, rateKeyFor } = __testing;

const treasury = Keypair.generate();
const ephemeral = Keypair.generate();
const recipient = Keypair.generate().publicKey;

/** A message transaction shaped the way the client builds one. */
function message({ units = 600_000, microLamports = 1_000 } = {}) {
  const tx = new Transaction();
  if (units !== null) tx.add(ComputeBudgetProgram.setComputeUnitLimit({ units }));
  if (microLamports !== null) tx.add(ComputeBudgetProgram.setComputeUnitPrice({ microLamports }));
  tx.add(SystemProgram.transfer({
    fromPubkey: ephemeral.publicKey,
    toPubkey: recipient,
    lamports: 0,
  }));
  tx.feePayer = treasury.publicKey;
  tx.recentBlockhash = 'GHtXQBsoZHVnNFa9YevAzFr17DJjgHXk3ycTKD5xD3Zi';
  return tx;
}

// --- 1. Priority fee ---------------------------------------------------------

// What the app actually sends has to keep working, or the fix is an outage.
assertTreasuryOnlyPaysFees(message(), treasury);
console.log('PASS: an ordinary client transaction is still accepted');

// The report: 1.4M units at 10,000,000 micro-lamports charged the treasury
// 14,010,000 lamports for one message.
assert.throws(
  () => assertTreasuryOnlyPaysFees(message({ units: 1_400_000, microLamports: 10_000_000 }), treasury),
  /above ceiling/,
  'the reported drain transaction was accepted',
);
console.log('PASS: the reported treasury-draining fee is refused');

// Neither ceiling alone binds, because the two multiply.
assert.throws(
  () => assertTreasuryOnlyPaysFees(message({ units: 1_400_000, microLamports: 19_000 }), treasury),
  /priority fee/,
  'a legal limit times a legal price still has to be checked',
);
console.log('PASS: limit and price are checked as a product, not separately');

// Solana keeps the last of a repeated instruction, so accepting two would mean
// checking a value the network then ignores.
{
  const tx = message();
  tx.add(ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 10_000_000 }));
  assert.throws(() => assertTreasuryOnlyPaysFees(tx, treasury), /duplicate/);
  console.log('PASS: a second price instruction is refused');
}

// The original check, still in place.
{
  const tx = message();
  tx.add(SystemProgram.transfer({
    fromPubkey: treasury.publicKey,
    toPubkey: recipient,
    lamports: 1_000_000,
  }));
  assert.throws(() => assertTreasuryOnlyPaysFees(tx, treasury), /treasury referenced/);
  console.log('PASS: an instruction that moves treasury lamports is still refused');
}

// --- 2. Blind token nonce canonicalisation -----------------------------------

const nonce = crypto.getRandomValues(new Uint8Array(32));
const canonical = bytesToB64u(nonce);

assert.equal(canonicalNonce(canonical), canonical, 'a canonical nonce must be accepted unchanged');
console.log('PASS: a normal token nonce is accepted');

// The report: swapping `_` for `/` leaves the decoded bytes identical, so the
// RSA signature still verifies - while the spent-token record is keyed by the
// string, so each spelling got its own slot.
if (canonical.includes('_') || canonical.includes('-')) {
  const respelled = canonical.replace(/_/g, '/').replace(/-/g, '+');
  assert.deepEqual(
    Array.from(b64uToBytes(respelled)),
    Array.from(nonce),
    'this test needs a nonce whose respelling decodes the same',
  );
  assert.equal(canonicalNonce(respelled), null, 'the respelled nonce was accepted');
  console.log('PASS: the reported respelling is refused');
}

for (const bad of [
  canonical + '=',              // padded
  canonical + 'A',              // too long
  canonical.slice(0, 42),       // too short
  bytesToB64u(crypto.getRandomValues(new Uint8Array(16))), // not 32 bytes
  'A'.repeat(43) + '!',
]) {
  assert.equal(canonicalNonce(bad), null, `accepted a non-canonical nonce: ${bad}`);
}
console.log('PASS: padded, short, long and foreign encodings are all refused');

// The last character of a 43-character base64url string carries two significant
// bits, so several characters decode to the same 32 bytes. Only one is canonical.
{
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let equivalents = 0;
  for (const ch of alphabet) {
    const candidate = canonical.slice(0, 42) + ch;
    if (candidate === canonical) continue;
    const sameBytes = Array.from(b64uToBytes(candidate)).every((b, i) => b === nonce[i]);
    if (sameBytes) {
      equivalents++;
      assert.equal(canonicalNonce(candidate), null, `accepted trailing-bit variant ${candidate}`);
    }
  }
  console.log(`PASS: ${equivalents} trailing-bit variants of the same nonce all refused`);
}

// --- 3. Subscription quota key ----------------------------------------------

// The report: the counter was keyed by the request's `account` field, which
// nobody signs, so one subscription got a fresh allowance per value sent.
const month = '2026-08';
const a = quotaKeyFor({ subscriptionId: 'apple-original-tx-1', account: 'accountA', month });
const b = quotaKeyFor({ subscriptionId: 'apple-original-tx-1', account: 'accountB', month });
assert.equal(a, b, 'the same subscription got two different counters');
console.log('PASS: one subscription is one counter, whatever account is sent');

const other = quotaKeyFor({ subscriptionId: 'apple-original-tx-2', account: 'accountA', month });
assert.notEqual(a, other, 'two subscriptions must not share a counter');
console.log('PASS: two subscriptions keep separate counters');

// Free tier has no subscription to key on, so it stays per account.
const free = quotaKeyFor({ subscriptionId: null, account: 'accountA', month });
assert.ok(free.includes('accountA'), 'the free tier is metered per account');
console.log('PASS: the free tier is still metered per account');

// The same report's second half: rotating the account also rotated the
// per-minute limiter. A verified subscription is now throttled as one caller,
// so the volume cap has a rate cap beside it.
assert.equal(
  rateKeyFor('apple-original-tx-1'),
  rateKeyFor('apple-original-tx-1'),
  'one subscription must throttle in one bucket',
);
assert.notEqual(
  rateKeyFor('apple-original-tx-1'),
  rateKeyFor('apple-original-tx-2'),
  'two subscriptions must not share a throttle bucket',
);
assert.equal(rateKeyFor(null), null, 'the free tier has no subscription to throttle');
console.log('PASS: one subscription throttles as one caller, whatever account is sent');

// --- 4. A spent token stays spent ------------------------------------------

// The report: the spent record self-deleted after 90 days while the signature
// stayed valid, so the same token bought a second sponsored transaction - once
// per cleanup cycle, indefinitely.
{
  const storage = new Map();
  let alarmAt = null;
  const state = {
    storage: {
      async get(key) { return storage.get(key); },
      async put(key, value) { storage.set(key, value); },
      async delete(key) { return storage.delete(key); },
      async deleteAll() { storage.clear(); },
      async setAlarm(time) { alarmAt = time; },
    },
    async blockConcurrencyWhile(cb) { return cb(); },
  };

  const object = new SpentTokenDO(state);
  const call = (path) => object.fetch(new Request(`https://do${path}`));

  assert.equal((await call('/claim')).status, 200, 'a fresh token must be claimable');
  assert.equal((await call('/commit')).status, 200);
  assert.equal((await call('/claim')).status, 409, 'an immediate reuse must be refused');

  assert.equal(alarmAt, null, 'a spent record must not schedule its own deletion');

  // Even if an alarm was scheduled by an older deployment, firing it must not
  // hand the token back.
  await object.alarm();
  assert.equal((await call('/claim')).status, 409, 'the cleanup made a spent token spendable again');
  console.log('PASS: a spent token stays spent, including after its old alarm fires');
}

console.log('\nALL SECURITY-REPORT REGRESSIONS PASSED');
