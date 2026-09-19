/**
 * Regressions for externally reported issues.
 * Run: npx tsx test/security-reports.test.mjs   (from relay/)

 * Three of the six reports were about this Worker:

 *   - a caller could choose the priority fee the treasury pays,
 *   - one blind token could be spent once per spelling of its nonce,
 *   - one subscription could get a fresh monthly allowance per `account` value.

 * Each test below fails against the code as it was.
 */
import assert from 'node:assert';
import * as x509 from '@peculiar/x509';
import { SignJWT } from 'jose';
import { Keypair, Transaction, PublicKey, ComputeBudgetProgram, SystemProgram } from '@solana/web3.js';
import { canonicalNonce, bytesToB64u, b64uToBytes } from '../src/blindtokens.ts';
import { __testing } from '../src/index.ts';
import { SpentTokenDO } from '../src/spenttokens.ts';
import { QuotaDO } from '../src/quotado.ts';

const { assertTreasuryOnlyPaysFees, verifyAppleJWS, quotaKeyFor, rateKeyFor } = __testing;

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

// --- 5. The treasury pays for two signatures, not for however many are sent ---

// The report: the guard bounded the priority fee but never the base fee, which
// is 5000 lamports per required signature. A caller could name its own keypairs
// as extra signers - accounts the treasury-reference check does not object to,
// because they belong to the caller - and we paid 5000 more for each one. The
// proof of concept reached 55,000 lamports on a message that costs 10,000.
{
  const MEMO = new PublicKey('MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr');
  const withExtraSigners = (n) => {
    const sender = Keypair.generate();
    const extra = Array.from({ length: n }, () => Keypair.generate());
    const tx = new Transaction();
    tx.add(ComputeBudgetProgram.setComputeUnitLimit({ units: 600_000 }));
    tx.add(ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 1000 }));
    tx.add({
      keys: [
        { pubkey: sender.publicKey, isSigner: true, isWritable: false },
        ...extra.map((k) => ({ pubkey: k.publicKey, isSigner: true, isWritable: false })),
      ],
      programId: MEMO,
      data: Buffer.from('e30=', 'base64'),
    });
    tx.feePayer = treasury.publicKey;
    tx.recentBlockhash = 'GHtXQBsoZHVnNFa9YevAzFr17DJjgHXk3ycTKD5xD3Zi';
    return tx;
  };

  assert.doesNotThrow(
    () => assertTreasuryOnlyPaysFees(withExtraSigners(0), treasury),
    'the ordinary two-signature message must still be signed',
  );
  console.log('PASS: a two-signature message is still accepted');

  for (const n of [1, 3, 8]) {
    assert.throws(
      () => assertTreasuryOnlyPaysFees(withExtraSigners(n), treasury),
      /too many signatures/,
      `${n + 2} signatures charge the treasury ${(n + 2) * 5000} lamports and must be refused`,
    );
  }
  console.log('PASS: extra signers, and the base fee they charge us, are refused');
}

// --- 6. One subscription, one monthly allowance, across both paths -----------

// The report: /issue metered `issued:<sub>:<month>` while /send metered
// `used:sub:<sub>:<month>`, each capped at the same allowance, so one
// subscription drew twice what it paid for.
{
  const month = '2026-09';
  const sub = 'apple-original-tx-1';
  const sendKey = quotaKeyFor({ subscriptionId: sub, account: 'device-a', month });
  const issueKey = quotaKeyFor({ subscriptionId: sub, account: sub, month });
  assert.equal(issueKey, sendKey, 'minting tokens must draw from the counter sends draw from');
  console.log('PASS: issuing and sending share one monthly counter');
}

// --- 7. A redeemed purchase stays redeemed ----------------------------------

// The report: the dedup record for a consumable pack self-deleted after 400
// days while the Apple transaction id stayed valid forever, so the same receipt
// credited another pack once per cleanup cycle.
{
  const store = new Map();
  let alarmAt = null;
  const state = {
    storage: {
      async get(k) { return store.get(k); },
      async put(k, v) { store.set(k, v); },
      async delete(k) { return store.delete(k); },
      async deleteAll() { store.clear(); },
      async setAlarm(t) { alarmAt = t; },
      async getAlarm() { return alarmAt; },
    },
    async blockConcurrencyWhile(cb) { return cb(); },
  };
  const object = new QuotaDO(state);
  const claim = async (ttlMs) => {
    const res = await object.fetch(new Request('https://do/claim', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ttlMs }),
    }));
    return res.json();
  };

  const ttl = 0;   // what index.ts now passes for a pack redemption
  assert.equal((await claim(ttl)).ok, true, 'the first redemption must succeed');
  assert.equal((await claim(ttl)).ok, false, 'an immediate re-redemption must be refused');
  assert.equal(alarmAt, null, 'a redemption record must not schedule its own deletion');

  // And if an older deployment left an alarm behind, firing it must not hand
  // the purchase back.
  await object.alarm();
  assert.equal((await claim(ttl)).ok, false, 'the cleanup made one purchase creditable twice');
  console.log('PASS: one purchase credits one pack, including after its old alarm fires');
}

// --- 5. Apple receipt chain: root pin is not a purpose check ------------------

// The report: the chain was pinned to Apple Root CA - G3 and nothing checked
// WHAT the leaf was. That root also anchors Apple Pay merchant certificates
// (Apple WWDR CA - G2, valid to 2029) and ordinary developer signing
// certificates (WWDR G6) — in both cases the caller generates the key pair and
// keeps the private key. So a caller could sign their own JWS claiming
// com.privamesh.pro.monthly and the relay accepted it as a paid entitlement:
// free PRO, unlimited /credit packs and blind tokens by rotating the
// transaction ids, all of it sponsored out of the treasury.
{
  x509.cryptoProvider.set(globalThis.crypto);
  const APPLE_RECEIPT_SIGNING_OID = '1.2.840.113635.100.6.11.1';
  const APPLE_WWDR_INTERMEDIATE_OID = '1.2.840.113635.100.6.2.1';
  const APPLE_PAY_INTERMEDIATE_OID = '1.2.840.113635.100.6.2.15';  // what WWDR G2 carries

  const day = 86_400_000;
  const notBefore = new Date(Date.now() - day);
  const notAfter = new Date(Date.now() + 365 * day);
  const b64 = (raw) => Buffer.from(raw).toString('base64');
  const ecKeys = (namedCurve) => crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve }, true, ['sign', 'verify']);
  // An Apple marker OID is an extension with an empty body; only its presence
  // is read, here and in Apple's own app-store-server-library.
  const marker = (oid) => new x509.Extension(oid, false, new Uint8Array(0));

  // A stand-in for Apple Root CA - G3, so the test needs no Apple secret. The
  // code under test is the real one; only the trust anchor is swapped.
  const rootKeys = await ecKeys('P-384');
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: '01', name: 'CN=Apple Root CA - G3 (stand-in)',
    notBefore, notAfter, keys: rootKeys,
    signingAlgorithm: { name: 'ECDSA', hash: 'SHA-384' },
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  });

  const intermediate = async (name, oids, ca = true) => {
    const keys = await ecKeys('P-384');
    const cert = await x509.X509CertificateGenerator.create({
      serialNumber: '02', subject: `CN=${name}`, issuer: root.subject,
      notBefore, notAfter, publicKey: keys.publicKey, signingKey: rootKeys.privateKey,
      signingAlgorithm: { name: 'ECDSA', hash: 'SHA-384' },
      extensions: [new x509.BasicConstraintsExtension(ca, undefined, true), ...oids.map(marker)],
    });
    return { cert, keys };
  };

  const leafUnder = async (issuer, subject, oids) => {
    const keys = await ecKeys('P-256');
    const cert = await x509.X509CertificateGenerator.create({
      serialNumber: '03', subject, issuer: issuer.cert.subject,
      notBefore, notAfter, publicKey: keys.publicKey, signingKey: issuer.keys.privateKey,
      signingAlgorithm: { name: 'ECDSA', hash: 'SHA-384' },
      extensions: oids.map(marker),
    });
    return { cert, keys };
  };

  const receiptFrom = (leaf, issuer, claims = {}) => new SignJWT({
    productId: 'com.privamesh.pro.monthly',
    bundleId: 'com.privamesh',
    transactionId: 't1',
    originalTransactionId: 's1',
    expiresDate: Date.now() + 30 * day,
    ...claims,
  }).setProtectedHeader({
    alg: 'ES256', x5c: [b64(leaf.cert.rawData), b64(issuer.cert.rawData)],
  }).sign(leaf.keys.privateKey);

  const env = { APPLE_ROOT_G3: root.toString('pem'), BUNDLE_ID: 'com.privamesh' };

  // What Apple actually sends has to keep working, or the fix is an outage.
  const appStoreCA = await intermediate(
    'Apple Worldwide Developer Relations Certification Authority', [APPLE_WWDR_INTERMEDIATE_OID]);
  const receiptSigner = await leafUnder(
    appStoreCA, 'CN=Prod ECC Mac App Store and iTunes Store Receipt Signing',
    [APPLE_RECEIPT_SIGNING_OID]);
  const claims = await verifyAppleJWS(await receiptFrom(receiptSigner, appStoreCA), env);
  assert.equal(claims.productId, 'com.privamesh.pro.monthly');
  console.log('PASS: a real App Store receipt chain is still accepted');

  // The report: an Apple Pay payment processing leaf under WWDR CA - G2. The
  // merchant made the CSR and holds the key; nothing in the leaf says receipt.
  const applePayCA = await intermediate(
    'Apple Worldwide Developer Relations CA - G2', [APPLE_PAY_INTERMEDIATE_OID]);
  const merchant = await leafUnder(applePayCA, 'CN=Apple Pay Payment Processing:merchant, O=Not Apple', []);
  await assert.rejects(
    verifyAppleJWS(await receiptFrom(merchant, applePayCA), env),
    /not an App Store receipt signing certificate|not the Apple WWDR App Store CA/,
    'a merchant-held certificate under the pinned root minted a PRO entitlement',
  );
  console.log('PASS: an Apple Pay merchant certificate is refused');

  // Same root, the App Store intermediate itself: an ordinary developer signing
  // certificate is issued under WWDR G6 and its key lives on the developer's Mac.
  const developer = await leafUnder(appStoreCA, 'CN=Apple Development: Attacker, O=Not Apple', []);
  await assert.rejects(
    verifyAppleJWS(await receiptFrom(developer, appStoreCA), env),
    /not an App Store receipt signing certificate/,
    'a developer signing certificate minted a PRO entitlement',
  );
  console.log('PASS: a developer signing certificate is refused');

  // The marker OIDs are presence-checked, so an attacker leaf that simply
  // carries them must still fail the chain: it has no Apple signature over it.
  const forgedCA = await intermediate('CN=Not Apple CA', [APPLE_WWDR_INTERMEDIATE_OID]);
  const selfKeys = await ecKeys('P-384');
  const offRoot = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: '04', name: 'CN=Not Apple Root', notBefore, notAfter, keys: selfKeys,
    signingAlgorithm: { name: 'ECDSA', hash: 'SHA-384' },
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  });
  const impostor = await leafUnder(forgedCA, 'CN=Impostor Receipt Signing', [APPLE_RECEIPT_SIGNING_OID]);
  await assert.rejects(
    verifyAppleJWS(await receiptFrom(impostor, forgedCA), { ...env, APPLE_ROOT_G3: offRoot.toString('pem') }),
    /not signed by Apple Root CA G3/,
    'a self-issued chain wearing the Apple marker OIDs was accepted',
  );
  console.log('PASS: the marker OIDs do not replace the root pin');

  // An end-entity certificate must not be usable in the intermediate slot.
  const notACA = await intermediate('Leaf pretending to be a CA', [APPLE_WWDR_INTERMEDIATE_OID], false);
  const under = await leafUnder(notACA, 'CN=Receipt Signing', [APPLE_RECEIPT_SIGNING_OID]);
  await assert.rejects(
    verifyAppleJWS(await receiptFrom(under, notACA), env),
    /not a CA certificate/,
    'a non-CA certificate signed for an intermediate',
  );
  console.log('PASS: a non-CA certificate cannot act as the intermediate');
}


console.log('\nALL SECURITY-REPORT REGRESSIONS PASSED');
