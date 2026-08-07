/**
 * End-to-end round trip for the RSA blind-signature token protocol.
 * Run: npx tsx test/blindtokens.test.mjs   (from relay/)
 *
 * Exercises the exact issuer/verifier code the Worker runs, plus the client
 * blind/unblind helpers, against a freshly generated 2048-bit RSA key. Verifies:
 *   1. a blinded->signed->unblinded token verifies,
 *   2. the signer never sees the token (blinded value differs from representative),
 *   3. tampered signature and wrong nonce both fail.
 */
import { generateKeyPairSync } from 'node:crypto';
import assert from 'node:assert';
import {
  loadPublicKey, loadPrivateKey, fdh, blind, unblind, blindSign, verifyToken,
  bytesToB64u, bigToBytes, bytesToBig, b64uToBytes,
} from '../src/blindtokens.ts';

// --- issuer key: reuse Node's RSA keygen, export as JWK (base64url n/e/d) ------
const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = privateKey.export({ format: 'jwk' });
const pub = loadPublicKey(jwk.n, jwk.e);
const priv = loadPrivateKey(jwk.n, jwk.e, jwk.d);
console.log(`issuer modulus: ${pub.k} bytes (${pub.k * 8} bit)`);

// --- client: choose a token nonce, blind it -----------------------------------
const nonce = crypto.getRandomValues(new Uint8Array(32));
const nonceB64u = bytesToB64u(nonce);
const m = await fdh(nonce, pub);                       // representative in Z_n

// random blinding factor r in [2, n-1]
let r;
do { r = bytesToBig(crypto.getRandomValues(new Uint8Array(pub.k))) % pub.n; } while (r < 2n);
const blinded = blind(m, r, pub);
const blindedB64u = bytesToB64u(bigToBytes(blinded, pub.k));

// signer must NOT be able to see the representative
assert.notStrictEqual(blinded % pub.n, m, 'blinded value equals representative — no blinding!');

// --- server: blind-sign --------------------------------------------------------
const blindSigB64u = blindSign(blindedB64u, priv);
const blindSigVal = bytesToBig(b64uToBytes(blindSigB64u));

// --- client: unblind -----------------------------------------------------------
const s = unblind(blindSigVal, r, pub);
const sigB64u = bytesToB64u(bigToBytes(s, pub.k));

// --- verify (what the Worker does at /send) ------------------------------------
assert.strictEqual(await verifyToken(nonceB64u, sigB64u, pub), true, 'valid token failed to verify');
console.log('PASS: valid token verifies');

// --- negatives -----------------------------------------------------------------
const tampered = new Uint8Array(b64uToBytes(sigB64u));
tampered[tampered.length - 1] ^= 0x01;
assert.strictEqual(await verifyToken(nonceB64u, bytesToB64u(tampered), pub), false, 'tampered sig verified');
console.log('PASS: tampered signature rejected');

const wrongNonce = bytesToB64u(crypto.getRandomValues(new Uint8Array(32)));
assert.strictEqual(await verifyToken(wrongNonce, sigB64u, pub), false, 'wrong nonce verified');
console.log('PASS: wrong nonce rejected');

// a forged signature (random) must not verify for any nonce
const forged = bytesToB64u(bigToBytes(bytesToBig(crypto.getRandomValues(new Uint8Array(pub.k))) % pub.n, pub.k));
assert.strictEqual(await verifyToken(nonceB64u, forged, pub), false, 'forged signature verified');
console.log('PASS: forged signature rejected');

console.log('\nALL BLIND-TOKEN TESTS PASSED');
