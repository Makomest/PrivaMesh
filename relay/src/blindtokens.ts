/**
 * RSA blind signatures for anonymous, unlinkable message tokens (RSA-FDH,
 * Chaum-style; the RFC 9474 RSABSSA family without the deterministic PSS
 * encoding — a plain full-domain hash into Z_n).
 *
 * WHY: today the client sends its Apple IAP receipt (JWS) on every /send, so the
 * relay can link an account token to an Apple purchase. Blind tokens break that
 * link entirely. The issuing step proves entitlement ONCE (with the receipt) and
 * mints a batch of tokens the relay signs BLINDLY — it never sees the token
 * values it signed. The spending step (/send) presents an unblinded token whose
 * signature the relay can verify but cannot correlate to any issuance. So the
 * relay learns "a valid token was spent", never "which account / which purchase".
 *
 * SECURITY NOTES (must hold before production):
 *   • Unlinkability is information-theoretic in the blinding factor r — it does
 *     NOT depend on constant-time bignum, so the non-CT BigInt below is fine for
 *     the privacy property. Forgery resistance rests on RSA (>=2048-bit modulus).
 *   • Double-spend prevention here is best-effort via KV (eventually consistent);
 *     a determined attacker could race two spends of one token across edges.
 *     Upgrade the spent-set to a Durable Object for strong single-spend. See
 *     handleSend in index.ts.
 *   • This is hand-rolled bignum crypto. It is deliberately small and auditable,
 *     but a vetted RSABSSA library is preferable long-term.
 *
 * No key material is hardcoded: the modulus/exponents come from env
 * (TOKEN_RSA_N / TOKEN_RSA_E / TOKEN_RSA_D), each base64url of a big-endian
 * integer. Only N and E are ever exposed (GET /pubkey); D stays a Worker secret.
 */

// ------------------------------------------------------------ base64url <-> bytes

export function b64uToBytes(s: string): Uint8Array {
  const pad = (4 - (s.length % 4)) % 4;
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat(pad);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function bytesToB64u(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ------------------------------------------------------------ bytes <-> bigint

function bytesToBig(bytes: Uint8Array): bigint {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  return n;
}

/** Big-endian, left-padded/truncated to exactly `len` bytes. Throws if it does
 *  not fit (a value >= 2^(8*len) would be silently corrupted otherwise). */
function bigToBytes(n: bigint, len: number): Uint8Array {
  const out = new Uint8Array(len);
  let v = n;
  for (let i = len - 1; i >= 0; i--) {
    out[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  if (v !== 0n) throw new Error('integer too large for field width');
  return out;
}

// ------------------------------------------------------------ modular arithmetic

function modpow(base: bigint, exp: bigint, mod: bigint): bigint {
  if (mod === 1n) return 0n;
  let result = 1n;
  let b = base % mod;
  if (b < 0n) b += mod;
  let e = exp;
  while (e > 0n) {
    if (e & 1n) result = (result * b) % mod;
    e >>= 1n;
    b = (b * b) % mod;
  }
  return result;
}

/** Extended Euclid modular inverse. Throws if a is not invertible mod m. */
function modinv(a: bigint, m: bigint): bigint {
  let [old_r, r] = [((a % m) + m) % m, m];
  let [old_s, s] = [1n, 0n];
  while (r !== 0n) {
    const q = old_r / r;
    [old_r, r] = [r, old_r - q * r];
    [old_s, s] = [s, old_s - q * s];
  }
  if (old_r !== 1n) throw new Error('not invertible');
  return ((old_s % m) + m) % m;
}

// ------------------------------------------------------------ RSA key wrapper

export interface IssuerKey {
  n: bigint;
  e: bigint;
  d?: bigint;   // present only on the signing (private) side
  k: number;    // modulus length in bytes
}

/** Minimum issuer modulus: 2048-bit. A smaller modulus is trivially factorable
 *  and would let anyone forge tokens, so we refuse to load one. */
const MIN_MODULUS_BYTES = 256;

export function loadPublicKey(nB64u: string, eB64u: string): IssuerKey {
  const n = bytesToBig(b64uToBytes(nB64u));
  const e = bytesToBig(b64uToBytes(eB64u));
  const k = byteLen(n);
  if (k < MIN_MODULUS_BYTES) {
    throw new Error(`issuer modulus too small: ${k * 8} bits (min ${MIN_MODULUS_BYTES * 8})`);
  }
  // Public exponent must be odd and >= 3. e = 1 makes the signature the message
  // (no security); an even e is not a valid RSA exponent.
  if (e < 3n || (e & 1n) === 0n) {
    throw new Error('invalid public exponent');
  }
  return { n, e, k };
}

export function loadPrivateKey(nB64u: string, eB64u: string, dB64u: string): IssuerKey {
  const key = loadPublicKey(nB64u, eB64u);
  key.d = bytesToBig(b64uToBytes(dB64u));
  return key;
}

function byteLen(n: bigint): number {
  let len = 0;
  let v = n;
  while (v > 0n) { v >>= 8n; len++; }
  return len;
}

// ------------------------------------------------------------ full-domain hash

/** MGF1-SHA256 expansion of `seed` to `len` bytes (PKCS#1 mask generation). */
async function mgf1(seed: Uint8Array, len: number): Promise<Uint8Array> {
  const out = new Uint8Array(len);
  let counter = 0;
  let pos = 0;
  while (pos < len) {
    const c = new Uint8Array(4);
    c[0] = (counter >>> 24) & 0xff;
    c[1] = (counter >>> 16) & 0xff;
    c[2] = (counter >>> 8) & 0xff;
    c[3] = counter & 0xff;
    const block = new Uint8Array(seed.length + 4);
    block.set(seed, 0);
    block.set(c, seed.length);
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', block));
    const take = Math.min(digest.length, len - pos);
    out.set(digest.subarray(0, take), pos);
    pos += take;
    counter++;
  }
  return out;
}

/**
 * Full-domain hash of a token nonce into Z_n. Domain-separated by a fixed label
 * so these signatures can never be confused with any other RSA operation on the
 * same key. Returns an integer in [0, n).
 */
export async function fdh(tokenNonce: Uint8Array, key: IssuerKey): Promise<bigint> {
  const label = new TextEncoder().encode('PrivaMesh-blind-token-v1');
  const seed = new Uint8Array(label.length + tokenNonce.length);
  seed.set(label, 0);
  seed.set(tokenNonce, label.length);
  // Expand to the full modulus width, then reduce mod n. Reduction is acceptable
  // for RSA-FDH and keeps the representative uniformly spread across Z_n.
  const wide = await mgf1(seed, key.k);
  return bytesToBig(wide) % key.n;
}

// ------------------------------------------------------------ sign / verify

/** Blind-sign a client-supplied blinded value: s' = blinded^d mod n. The signer
 *  learns nothing about the underlying token (that is the blinding guarantee). */
export function blindSign(blindedB64u: string, key: IssuerKey): string {
  if (key.d === undefined) throw new Error('private key required to sign');
  const blinded = bytesToBig(b64uToBytes(blindedB64u));
  if (blinded <= 0n || blinded >= key.n) throw new Error('blinded value out of range');
  const sig = modpow(blinded, key.d, key.n);
  return bytesToB64u(bigToBytes(sig, key.k));
}

/** Verify an unblinded token: s^e mod n == FDH(nonce). Constant-timeness is not
 *  required — a forgery must satisfy this for a nonce the signer never signed,
 *  which is the RSA one-more-forgery assumption. */
export async function verifyToken(nonceB64u: string, sigB64u: string, key: IssuerKey): Promise<boolean> {
  let s: bigint;
  let nonce: Uint8Array;
  try {
    s = bytesToBig(b64uToBytes(sigB64u));
    nonce = b64uToBytes(nonceB64u);
  } catch {
    return false;
  }
  if (s <= 0n || s >= key.n) return false;
  const recovered = modpow(s, key.e, key.n);
  const expected = await fdh(nonce, key);
  return recovered === expected;
}

// ------------------------------------------------------------ client helpers
// (Exported for the node round-trip test in test/blindtokens.test.mjs; the Swift
//  client re-implements blind/unblind natively. Kept here so the protocol has a
//  single source of truth to test against.)

export function blind(mNonceRepresentative: bigint, r: bigint, key: IssuerKey): bigint {
  // blinded = m * r^e mod n
  return (mNonceRepresentative * modpow(r, key.e, key.n)) % key.n;
}

export function unblind(blindSigValue: bigint, r: bigint, key: IssuerKey): bigint {
  // s = s' * r^-1 mod n
  return (blindSigValue * modinv(r, key.n)) % key.n;
}

export { modpow, modinv, bytesToBig, bigToBytes };
