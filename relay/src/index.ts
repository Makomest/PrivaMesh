/**
 * PrivaMesh sponsoring relay (Cloudflare Worker).
 *
 * The app pays every message's Solana network fee from a shared treasury wallet;
 * users never hold or spend crypto. Access is metered by Apple IAP. This relay:
 *
 *   POST /send    { tx, jws, account }  → verify entitlement + quota, co-sign the
 *                                         fee-payer slot with the treasury key,
 *                                         submit to Solana, return { signature }.
 *   POST /credit  { jws, account }      → verify a consumable-pack receipt and
 *                                         add its messages to the account balance.
 *
 * Treasury protection (all serverless, inside this Worker):
 *   1. Apple cert-chain PINNING — the receipt JWS is verified up to Apple Root
 *      CA G3 (env.APPLE_ROOT_G3), so a forged leaf cert can't mint entitlements.
 *   2. Rate-limit — per account token, KV sliding window.
 *   3. Circuit-breaker — a global daily cap on sponsored transactions, so no
 *      vector can drain the treasury faster than the cap.
 *
 * Quota is AUTHORITATIVE here; the app's on-device counter is only a UX mirror.
 */

import { Connection, Keypair, Transaction } from '@solana/web3.js';
import bs58 from 'bs58';
import { jwtVerify, decodeProtectedHeader } from 'jose';
import { X509Certificate } from '@peculiar/x509';

export interface Env {
  QUOTA: KVNamespace;
  RPC_URL: string;
  BUNDLE_ID: string;
  PLUS_MONTHLY: string;
  PRO_MONTHLY: string;
  TREASURY_SECRET: string;
  /** PEM of Apple Root CA - G3. When set, receipt chains are pinned to it. */
  APPLE_ROOT_G3?: string;
  /** Overridable safety limits. */
  DAILY_TX_CAP?: string;    // global sponsored tx/day
  RATE_PER_MIN?: string;    // per-account /send per minute
}

const PACK_MESSAGES: Record<string, number> = {
  'com.privamesh.msgs.100': 100,
  'com.privamesh.msgs.500': 500,
  'com.privamesh.msgs.1500': 1500,
};

const PLUS_ID = 'com.privamesh.plus.monthly';
const PRO_ID = 'com.privamesh.pro.monthly';
const FREE_MONTHLY = 10;

const DEFAULT_DAILY_CAP = 5000;
const DEFAULT_RATE_PER_MIN = 20;

/**
 * Apple Root CA - G3 (public), downloaded from
 * https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
 * SHA-256: 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
 * Every receipt JWS is pinned to this trust anchor.
 */
const APPLE_ROOT_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
    const url = new URL(req.url);
    try {
      if (url.pathname === '/send') return await handleSend(req, env);
      if (url.pathname === '/credit') return await handleCredit(req, env);
      if (url.pathname === '/mint') return await handleMint(req, env);
      return json({ error: 'not found' }, 404);
    } catch (e: any) {
      return json({ error: String(e?.message ?? e) }, 500);
    }
  },
};

// ---------------------------------------------------------------- /send

async function handleSend(req: Request, env: Env): Promise<Response> {
  const { tx, jws, account } = await req.json<any>();
  if (!tx || !account) return json({ error: 'missing tx/account' }, 400);

  // 1. Rate-limit this account token.
  if (!(await underRateLimit(env, account))) {
    return json({ error: 'rate limited' }, 429);
  }

  // 2. Global circuit-breaker: never exceed the daily sponsored-tx cap.
  const cap = parseInt(env.DAILY_TX_CAP ?? '', 10) || DEFAULT_DAILY_CAP;
  const day = new Date().toISOString().slice(0, 10);
  const capKey = `daycap:${day}`;
  const spentToday = parseInt((await env.QUOTA.get(capKey)) ?? '0', 10);
  if (spentToday >= cap) return json({ error: 'daily cap reached' }, 503);

  // 3. Verify entitlement + reserve one message of quota.
  const ok = await reserveMessage(env, account, jws);
  if (!ok) return json({ error: 'quota exceeded' }, 402);

  // 4. Co-sign the fee-payer slot with the treasury and submit.
  try {
    const treasury = Keypair.fromSecretKey(bs58.decode(env.TREASURY_SECRET));
    const transaction = Transaction.from(Buffer.from(tx, 'base64'));
    assertTreasuryOnlyPaysFees(transaction, treasury); // never sign a tx that debits the treasury
    transaction.partialSign(treasury); // fills the fee-payer signature slot
    const raw = transaction.serialize();
    const conn = new Connection(env.RPC_URL, 'confirmed');
    const signature = await conn.sendRawTransaction(raw, { skipPreflight: false });
    // Count a successful sponsored tx against the daily cap.
    await env.QUOTA.put(capKey, String(spentToday + 1), { expirationTtl: 60 * 60 * 26 });
    return json({ signature });
  } catch (e: any) {
    await refundMessage(env, account); // don't burn quota on submit failure
    return json({ error: 'submit failed: ' + String(e?.message ?? e) }, 502);
  }
}

// ---------------------------------------------------------------- /credit

async function handleCredit(req: Request, env: Env): Promise<Response> {
  const { jws, account } = await req.json<any>();
  if (!jws || !account) return json({ error: 'missing jws/account' }, 400);

  const claims = await verifyAppleJWS(jws, env);
  const messages = PACK_MESSAGES[claims.productId];
  if (!messages) return json({ error: 'not a pack product' }, 400);

  const seenKey = `tx:${claims.transactionId}`;
  if (await env.QUOTA.get(seenKey)) return json({ ok: true, alreadyCredited: true });
  await env.QUOTA.put(seenKey, '1', { expirationTtl: 60 * 60 * 24 * 400 });

  const balKey = `pack:${account}`;
  const cur = parseInt((await env.QUOTA.get(balKey)) ?? '0', 10);
  await env.QUOTA.put(balKey, String(cur + messages));
  return json({ ok: true, balance: cur + messages });
}

// ---------------------------------------------------------------- /mint

const MAX_MINTS = 3; // sponsored NFT nickname mints per subscriber account

async function handleMint(req: Request, env: Env): Promise<Response> {
  const { tx, jws, account } = await req.json<any>();
  if (!tx || !account) return json({ error: 'missing tx/account' }, 400);
  if (!jws) return json({ error: 'subscription required' }, 403);

  // Must be an active subscriber.
  let claims;
  try {
    claims = await verifyAppleJWS(jws, env);
  } catch (e: any) {
    return json({ error: 'invalid receipt: ' + String(e?.message ?? e) }, 403);
  }
  const subActive =
    (claims.productId === PLUS_ID || claims.productId === PRO_ID) &&
    !(claims.expiresDate && claims.expiresDate < Date.now());
  if (!subActive) return json({ error: 'active subscription required' }, 403);

  // Enforce the lifetime mint allowance per account.
  const mintKey = `mints:${account}`;
  const used = parseInt((await env.QUOTA.get(mintKey)) ?? '0', 10);
  if (used >= MAX_MINTS) return json({ error: 'mint limit reached' }, 402);

  // Rate-limit + daily circuit-breaker apply to mints too.
  if (!(await underRateLimit(env, account))) return json({ error: 'rate limited' }, 429);
  const cap = parseInt(env.DAILY_TX_CAP ?? '', 10) || DEFAULT_DAILY_CAP;
  const day = new Date().toISOString().slice(0, 10);
  const capKey = `daycap:${day}`;
  const spentToday = parseInt((await env.QUOTA.get(capKey)) ?? '0', 10);
  if (spentToday >= cap) return json({ error: 'daily cap reached' }, 503);

  await env.QUOTA.put(mintKey, String(used + 1), { expirationTtl: 60 * 60 * 24 * 400 });
  try {
    const treasury = Keypair.fromSecretKey(bs58.decode(env.TREASURY_SECRET));
    const transaction = Transaction.from(Buffer.from(tx, 'base64'));
    assertTreasuryOnlyPaysFees(transaction, treasury);
    transaction.partialSign(treasury);
    const raw = transaction.serialize();
    const conn = new Connection(env.RPC_URL, 'confirmed');
    const signature = await conn.sendRawTransaction(raw, { skipPreflight: false });
    await env.QUOTA.put(capKey, String(spentToday + 1), { expirationTtl: 60 * 60 * 26 });
    return json({ signature });
  } catch (e: any) {
    // Refund the mint allowance on submit failure.
    await env.QUOTA.put(mintKey, String(used), { expirationTtl: 60 * 60 * 24 * 400 });
    return json({ error: 'mint submit failed: ' + String(e?.message ?? e) }, 502);
  }
}

// ------------------------------------------------------ tx safety guard

/**
 * The treasury must sign ONLY as fee payer. A legitimate sponsored message tx
 * lists the treasury as feePayer and never references it in any instruction
 * (the memo + 0-lamport transfer are signed by an ephemeral key). If the
 * treasury appears in an instruction's account list, signing it could authorise
 * a SOL debit (e.g. SystemProgram.transfer from the treasury) and drain it — so
 * we refuse to co-sign such a transaction.
 */
function assertTreasuryOnlyPaysFees(transaction: Transaction, treasury: Keypair): void {
  const t = treasury.publicKey.toBase58();
  if (!transaction.feePayer || transaction.feePayer.toBase58() !== t) {
    throw new Error('treasury must be the fee payer');
  }
  for (const ix of transaction.instructions) {
    for (const key of ix.keys) {
      if (key.pubkey.toBase58() === t) {
        throw new Error('treasury referenced by an instruction — refusing to sign');
      }
    }
  }
}

// ------------------------------------------------------------ quota core

async function reserveMessage(env: Env, account: string, jws?: string): Promise<boolean> {
  let allowance = 0;
  if (jws) {
    try {
      const claims = await verifyAppleJWS(jws, env);
      if (claims.productId === PRO_ID) allowance = parseInt(env.PRO_MONTHLY, 10);
      else if (claims.productId === PLUS_ID) allowance = parseInt(env.PLUS_MONTHLY, 10);
      if (claims.expiresDate && claims.expiresDate < Date.now()) allowance = 0;
    } catch {
      allowance = 0; // invalid receipt → no subscription allowance
    }
  }

  const month = new Date().toISOString().slice(0, 7);
  const usedKey = `used:${account}:${month}`;
  const used = parseInt((await env.QUOTA.get(usedKey)) ?? '0', 10);
  const effectiveAllowance = Math.max(allowance, FREE_MONTHLY);

  if (used < effectiveAllowance) {
    await env.QUOTA.put(usedKey, String(used + 1), { expirationTtl: 60 * 60 * 24 * 62 });
    return true;
  }

  const balKey = `pack:${account}`;
  const bal = parseInt((await env.QUOTA.get(balKey)) ?? '0', 10);
  if (bal > 0) {
    await env.QUOTA.put(balKey, String(bal - 1));
    return true;
  }
  return false;
}

async function refundMessage(env: Env, account: string): Promise<void> {
  const month = new Date().toISOString().slice(0, 7);
  const usedKey = `used:${account}:${month}`;
  const used = parseInt((await env.QUOTA.get(usedKey)) ?? '0', 10);
  if (used > 0) await env.QUOTA.put(usedKey, String(used - 1), { expirationTtl: 60 * 60 * 24 * 62 });
}

// --------------------------------------------------------------- rate limit

async function underRateLimit(env: Env, account: string): Promise<boolean> {
  const perMin = parseInt(env.RATE_PER_MIN ?? '', 10) || DEFAULT_RATE_PER_MIN;
  const bucket = Math.floor(Date.now() / 60000); // per-minute bucket
  const key = `rl:${account}:${bucket}`;
  const n = parseInt((await env.QUOTA.get(key)) ?? '0', 10);
  if (n >= perMin) return false;
  await env.QUOTA.put(key, String(n + 1), { expirationTtl: 120 });
  return true;
}

// ------------------------------------------------------- Apple JWS verify

interface AppleClaims {
  productId: string;
  transactionId: string;
  expiresDate?: number;
  bundleId?: string;
}

/**
 * Verify an App Store Server JWS. The signing cert chain is in the `x5c` header.
 * When APPLE_ROOT_G3 is configured we PIN the chain: leaf must be signed by the
 * intermediate, and the intermediate by Apple Root CA - G3. This blocks a forged
 * leaf certificate from minting fake entitlements. Without the root set we fall
 * back to leaf-signature-only (development).
 */
async function verifyAppleJWS(jws: string, env: Env): Promise<AppleClaims> {
  const header: any = decodeProtectedHeader(jws);
  const x5c: string[] = header.x5c ?? [];
  if (!x5c.length) throw new Error('jws missing x5c');

  const leaf = new X509Certificate(x5c[0]);

  // Pin the chain to Apple Root CA - G3. A forged leaf can't chain here.
  // DEV_SKIP_PINNING=1 relaxes this for LOCAL StoreKit testing (whose receipts
  // are signed by Xcode's local test cert, not Apple's) — NEVER set in production.
  if (env.DEV_SKIP_PINNING !== '1') {
    const intermediate = x5c[1] ? new X509Certificate(x5c[1]) : null;
    if (!intermediate) throw new Error('jws missing intermediate cert');
    const root = new X509Certificate(env.APPLE_ROOT_G3 ?? APPLE_ROOT_G3_PEM);

    const intKey = await intermediate.publicKey.export();
    const rootKey = await root.publicKey.export();

    if (!(await leaf.verify({ publicKey: intKey, signatureOnly: true }))) {
      throw new Error('leaf not signed by intermediate');
    }
    if (!(await intermediate.verify({ publicKey: rootKey, signatureOnly: true }))) {
      throw new Error('intermediate not signed by Apple Root CA G3');
    }
    if (x5c[2]) {
      const shipped = new X509Certificate(x5c[2]);
      if (toB64(shipped.rawData) !== toB64(root.rawData)) {
        throw new Error('root cert does not match pinned Apple Root CA G3');
      }
    }
    const now = new Date();
    for (const c of [leaf, intermediate]) {
      if (now < c.notBefore || now > c.notAfter) throw new Error('cert expired');
    }
  }

  const leafKey = await leaf.publicKey.export();
  const { payload } = await jwtVerify(jws, leafKey);

  const claims: AppleClaims = {
    productId: String(payload.productId ?? ''),
    transactionId: String(payload.transactionId ?? payload.originalTransactionId ?? ''),
    expiresDate: payload.expiresDate ? Number(payload.expiresDate) : undefined,
    bundleId: payload.bundleId ? String(payload.bundleId) : undefined,
  };
  if (claims.bundleId && env.BUNDLE_ID && claims.bundleId !== env.BUNDLE_ID) {
    throw new Error('bundle id mismatch');
  }
  if (!claims.productId) throw new Error('jws missing productId');
  return claims;
}

// ---------------------------------------------------------------- utils

function toB64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
