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
import {
  loadPublicKey, loadPrivateKey, blindSign, verifyToken,
  type IssuerKey,
} from './blindtokens';
import { SpentTokenDO } from './spenttokens';
import { QuotaDO } from './quotado';

// Durable Object classes must be exported from the Worker entry module.
export { SpentTokenDO, QuotaDO };

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
  DAILY_TX_CAP?: string;    // global sponsored tx/day (all tiers)
  FREE_DAILY_CAP?: string;  // global FREE-tier sponsored tx/day (sybil ceiling)
  RATE_PER_MIN?: string;    // per-account /send per minute
  /**
   * Relaxes Apple cert-chain pinning for LOCAL StoreKit testing only. MUST be
   * unset in production; the Worker refuses to start a privileged request while
   * it is '1' unless ALLOW_INSECURE is also set (an explicit dev acknowledgement).
   */
  DEV_SKIP_PINNING?: string;
  ALLOW_INSECURE?: string;
  /**
   * Blind-token issuer RSA key, base64url of big-endian integers. N and E are
   * public (served at GET /pubkey); D is a Worker SECRET and never leaves.
   *   wrangler secret put TOKEN_RSA_N   (also fine as a [vars] entry — it's public)
   *   wrangler secret put TOKEN_RSA_E   (typically AQAB == 65537)
   *   wrangler secret put TOKEN_RSA_D   (SECRET — the signing exponent)
   * When unset, the anonymous-token endpoints are disabled and the relay keeps
   * working on the legacy receipt path, so this rolls out without a flag day.
   */
  TOKEN_RSA_N?: string;
  TOKEN_RSA_E?: string;
  TOKEN_RSA_D?: string;
  /** Strong single-spend for blind tokens. When bound, the token /send path
   *  claims each token in its own Durable Object (serialized, strongly
   *  consistent) instead of the eventually-consistent KV `spent:` set. */
  SPENT?: DurableObjectNamespace;
  /** Strongly-consistent atomic counters for the money-critical paths (issuance
   *  budget, pack credit dedup, per-account quota, daily circuit-breaker). When
   *  bound, these counters are raced-safe; without it they fall back to the
   *  eventually-consistent KV counters (best-effort, for a partial deploy). */
  QUOTA_DO?: DurableObjectNamespace;
  /** Max tokens a single receipt may mint per month (defaults to the tier's
   *  monthly allowance). A hard ceiling on issuance abuse. */
  ISSUE_BATCH_MAX?: string;
}

// TTLs (ms) for self-cleaning DO counters. Match the old KV expirations.
const TTL_MONTH_MS = 62 * 24 * 60 * 60 * 1000;
const TTL_DAY_MS = 26 * 60 * 60 * 1000;
const TTL_CREDIT_MS = 400 * 24 * 60 * 60 * 1000;

// --------------------------------------------------- atomic counter helpers
// Backed by QuotaDO (strongly consistent) when bound; otherwise fall back to the
// legacy KV get/put (eventually consistent — a partial-deploy safety net only).

async function quotaCall(env: Env, key: string, op: string, body: any = {}): Promise<any> {
  const stub = env.QUOTA_DO!.get(env.QUOTA_DO!.idFromName(key));
  const res = await stub.fetch(`https://do${op}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return res.json();
}

/** Atomically grant up to `want` units of `key` without exceeding `max`. */
async function reserveN(env: Env, key: string, max: number, want: number, ttlMs: number): Promise<number> {
  if (env.QUOTA_DO) {
    const r = await quotaCall(env, key, '/reserve', { max, want, ttlMs });
    return Number(r.granted) || 0;
  }
  const cur = parseInt((await env.QUOTA.get(key)) ?? '0', 10);
  const granted = Math.max(0, Math.min(want, max - cur));
  if (granted > 0) await env.QUOTA.put(key, String(cur + granted), { expirationTtl: Math.floor(ttlMs / 1000) });
  return granted;
}

async function refundCounter(env: Env, key: string, by = 1): Promise<void> {
  if (env.QUOTA_DO) { await quotaCall(env, key, '/refund', { by }); return; }
  const cur = parseInt((await env.QUOTA.get(key)) ?? '0', 10);
  if (cur > 0) await env.QUOTA.put(key, String(Math.max(0, cur - by)), { expirationTtl: 60 * 60 * 24 * 62 });
}

/** True only the FIRST time `key` is claimed — idempotent dedup. */
async function claimOnce(env: Env, key: string, ttlMs: number): Promise<boolean> {
  if (env.QUOTA_DO) {
    const r = await quotaCall(env, key, '/claim', { ttlMs });
    return !!r.ok;
  }
  if (await env.QUOTA.get(key)) return false;
  await env.QUOTA.put(key, '1', { expirationTtl: Math.floor(ttlMs / 1000) });
  return true;
}

async function addBalance(env: Env, key: string, amount: number): Promise<number> {
  if (env.QUOTA_DO) {
    const r = await quotaCall(env, key, '/add', { amount });
    return Number(r.value) || 0;
  }
  const cur = parseInt((await env.QUOTA.get(key)) ?? '0', 10);
  await env.QUOTA.put(key, String(cur + amount));
  return cur + amount;
}

/** Decrement `key` by 1 iff it is > 0. Returns whether a unit was spent. */
async function spendBalance(env: Env, key: string): Promise<boolean> {
  if (env.QUOTA_DO) {
    const r = await quotaCall(env, key, '/spend', {});
    return !!r.ok;
  }
  const cur = parseInt((await env.QUOTA.get(key)) ?? '0', 10);
  if (cur <= 0) return false;
  await env.QUOTA.put(key, String(cur - 1));
  return true;
}

const DEFAULT_ISSUE_BATCH_MAX = 64; // tokens per /issue call, independent of tier

const PACK_MESSAGES: Record<string, number> = {
  'com.privamesh.msgs.100': 100,
  'com.privamesh.msgs.500': 500,
  'com.privamesh.msgs.1500': 1500,
};

const PLUS_ID = 'com.privamesh.plus.monthly';
const PRO_ID = 'com.privamesh.pro.monthly';
const FREE_MONTHLY = 10;

const DEFAULT_DAILY_CAP = 5000;
const DEFAULT_FREE_DAILY_CAP = 500;   // global ceiling on FREE-tier sponsored tx/day
const DEFAULT_RATE_PER_MIN = 20;

/**
 * Guard against shipping with pinning disabled. DEV_SKIP_PINNING bypasses Apple
 * receipt verification and must never be live in production; requiring an
 * explicit ALLOW_INSECURE alongside it makes an accidental deploy fail closed.
 */
function assertPinningSafe(env: Env): void {
  if (env.DEV_SKIP_PINNING === '1' && env.ALLOW_INSECURE !== '1') {
    throw new Error('refusing to run: DEV_SKIP_PINNING set without ALLOW_INSECURE');
  }
}

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
    const url = new URL(req.url);
    // Public issuer key is the only GET — the client needs (n, e) to blind.
    if (req.method === 'GET' && url.pathname === '/pubkey') return handlePubkey(env);
    if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
    try {
      assertPinningSafe(env);
      if (url.pathname === '/send') return await handleSend(req, env);
      if (url.pathname === '/issue') return await handleIssue(req, env);
      if (url.pathname === '/credit') return await handleCredit(req, env);
      return json({ error: 'not found' }, 404);
    } catch (e: any) {
      // Log full detail server-side; never leak internal exception text to callers.
      console.error('relay error', e);
      return json({ error: 'internal error' }, 500);
    }
  },
};

// ------------------------------------------------------- blind-token issuer

/** Load the issuer key from env, or null if anonymous tokens aren't configured. */
function issuerPrivateKey(env: Env): IssuerKey | null {
  if (!env.TOKEN_RSA_N || !env.TOKEN_RSA_E || !env.TOKEN_RSA_D) return null;
  return loadPrivateKey(env.TOKEN_RSA_N, env.TOKEN_RSA_E, env.TOKEN_RSA_D);
}
function issuerPublicKey(env: Env): IssuerKey | null {
  if (!env.TOKEN_RSA_N || !env.TOKEN_RSA_E) return null;
  return loadPublicKey(env.TOKEN_RSA_N, env.TOKEN_RSA_E);
}

/** GET /pubkey → { n, e } (base64url). Lets the client blind without any key
 *  baked into the app binary. Empty object when tokens are unconfigured. */
function handlePubkey(env: Env): Response {
  if (!env.TOKEN_RSA_N || !env.TOKEN_RSA_E) return json({ enabled: false });
  return json({ enabled: true, n: env.TOKEN_RSA_N, e: env.TOKEN_RSA_E });
}

/**
 * POST /issue { jws, blinded: [b64u,...] } → { sigs: [b64u,...] }
 *
 * Proves entitlement ONCE with the Apple receipt, then blind-signs up to the
 * tier's remaining monthly token budget. The relay never sees the token values
 * (they are blinded), so it cannot later link a spent token to this receipt.
 *
 * Issuance is metered per Apple ORIGINAL transaction id + month, so a single
 * subscription can't mint more than its monthly allowance regardless of how many
 * times /issue is called or how many device accounts request tokens.
 */
async function handleIssue(req: Request, env: Env): Promise<Response> {
  const key = issuerPrivateKey(env);
  if (!key) return json({ error: 'tokens not configured' }, 501);

  const { jws, blinded } = await req.json<any>();
  if (!Array.isArray(blinded) || blinded.length === 0) {
    return json({ error: 'missing blinded[]' }, 400);
  }
  const batchMax = parseInt(env.ISSUE_BATCH_MAX ?? '', 10) || DEFAULT_ISSUE_BATCH_MAX;
  if (blinded.length > batchMax) return json({ error: 'batch too large' }, 400);

  // Anonymous tokens are a PAID feature only. A spent token carries no identity,
  // so the relay can't apply a per-user free-tier ceiling at spend time; the only
  // sound sybil anchor is the Apple ORIGINAL transaction id, which exists only for
  // an active paid subscription. Free/expired users keep the legacy account path
  // at /send (metered per seed-account, non-anonymous). This keeps the treasury
  // sybil-safe WITHOUT weakening the anonymity of paying users.
  if (!jws) return json({ error: 'subscription required for anonymous tokens' }, 402);
  let allowance = 0;
  let subject = '';
  try {
    const claims = await verifyAppleJWS(jws, env);
    if (claims.expiresDate && claims.expiresDate < Date.now()) allowance = 0;
    else if (claims.productId === PRO_ID) allowance = parseInt(env.PRO_MONTHLY, 10) || 0;
    else if (claims.productId === PLUS_ID) allowance = parseInt(env.PLUS_MONTHLY, 10) || 0;
    // Meter by the ORIGINAL transaction id so renewals/restores of one
    // subscription share a monthly budget (a new transactionId per renewal must
    // NOT grant a fresh allowance — that would let one sub farm >monthly tokens).
    subject = claims.originalTransactionId || '';
  } catch {
    return json({ error: 'invalid receipt' }, 402);
  }
  if (allowance <= 0 || !subject) {
    return json({ error: 'active subscription required' }, 402);
  }

  // Rate-limit issuance per subscription. Blind signing + the Apple cert-chain
  // verify above are CPU-heavy, so a replayed receipt must not be able to hammer
  // /issue. The monthly budget already bounds token COUNT; this bounds call RATE.
  if (!(await underRateLimit(env, `issue:${subject}`))) {
    return json({ error: 'rate limited' }, 429);
  }

  // Sign FIRST (a pure function of each blinded value — no state touched, so bad
  // input is rejected before any budget is consumed), THEN reserve the budget
  // atomically. Reserving after signing means a concurrent /issue race can never
  // over-mint: reserveN grants only up to (allowance - already) inside a single
  // serialized DO op, so the sum of grants across racers can't exceed allowance.
  const month = new Date().toISOString().slice(0, 7);
  const issuedKey = `issued:${subject}:${month}`;
  const allSigs: string[] = [];
  for (let i = 0; i < blinded.length; i++) {
    try {
      allSigs.push(blindSign(String(blinded[i]), key));
    } catch (e) {
      console.error('blindSign failed', e);
      return json({ error: 'bad blinded value' }, 400);
    }
  }
  const grant = await reserveN(env, issuedKey, allowance, blinded.length, TTL_MONTH_MS);
  if (grant <= 0) return json({ error: 'issuance budget exhausted', sigs: [] }, 402);
  return json({ sigs: allSigs.slice(0, grant) });
}

// ---------------------------------------------------------------- /send

async function handleSend(req: Request, env: Env): Promise<Response> {
  const { tx, jws, account, token } = await req.json<any>();
  if (!tx) return json({ error: 'missing tx' }, 400);
  // Two auth modes: anonymous blind token (preferred) or the legacy receipt+
  // account path. A token, when present and configured, is used exclusively —
  // it carries no identity, so nothing about the sender reaches the relay.
  const issuerPub = issuerPublicKey(env);
  const useToken = !!token && !!issuerPub;
  if (!useToken && !account) return json({ error: 'missing token/account' }, 400);

  // Deserialize once — needed for the treasury-safety guard and the discovery
  // nickname check below.
  const treasury = Keypair.fromSecretKey(bs58.decode(env.TREASURY_SECRET));
  let transaction: Transaction;
  try {
    transaction = Transaction.from(Buffer.from(tx, 'base64'));
    assertTreasuryOnlyPaysFees(transaction, treasury); // never sign a tx that debits the treasury
  } catch (e) {
    console.error('bad tx', e);
    return json({ error: 'bad transaction' }, 400);
  }

  // Discovery nickname publishes are inherently PUBLIC identity and need a stable
  // owner id for uniqueness — impossible with an anonymous token. They therefore
  // always take the account path; a token send that carries a discovery publish
  // is rejected so a client can't sidestep ownership.
  const nick = extractDiscoveryNick(transaction);
  if (useToken && nick) {
    return json({ error: 'discovery publish requires account path' }, 400);
  }

  // Global circuit-breaker: never exceed the daily sponsored-tx cap. Applies to
  // BOTH paths — it is the treasury's last line of defence regardless of auth.
  // Reserved ATOMICALLY at each submit point below (a raced get/put here would let
  // a concurrent burst blow past the cap — the whole point of the breaker), and
  // refunded if the submit fails so only real submissions are counted.
  const cap = parseInt(env.DAILY_TX_CAP ?? '', 10) || DEFAULT_DAILY_CAP;
  const day = new Date().toISOString().slice(0, 10);
  const capKey = `daycap:${day}`;

  // ---- Anonymous blind-token path: no account, no receipt, no identity. -------
  if (useToken) {
    const nonce = String(token.t ?? '');
    const sig = String(token.sig ?? '');
    if (!nonce || !sig) return json({ error: 'malformed token' }, 400);
    // The token's own signature IS the quota proof (already paid at /issue).
    if (!(await verifyToken(nonce, sig, issuerPub!))) {
      return json({ error: 'invalid token' }, 402);
    }

    // --- Strong single-spend via Durable Object (preferred). ------------------
    if (env.SPENT) {
      const stub = env.SPENT.get(env.SPENT.idFromName(nonce));
      // Atomically CLAIM the token before submitting. A concurrent spend of the
      // same token hits the same DO and is rejected here — no double-charge.
      const claim = await stub.fetch('https://do/claim');
      if (!claim.ok) return json({ error: 'token already spent' }, 409);
      // Atomically reserve daily-cap headroom before spending the token.
      if ((await reserveN(env, capKey, cap, 1, TTL_DAY_MS)) <= 0) {
        await stub.fetch('https://do/release');
        return json({ error: 'daily cap reached' }, 503);
      }
      const conn = new Connection(env.RPC_URL, 'confirmed');
      try {
        transaction.partialSign(treasury);
        const raw = transaction.serialize();
        const signature = await conn.sendRawTransaction(raw, { skipPreflight: false });
        await stub.fetch('https://do/commit');    // finalize spent
        return json({ signature });
      } catch (e) {
        console.error('submit failed (token/DO)', e);
        await refundCounter(env, capKey);         // uncount the reserved slot
        // Only un-spend the token if the tx did NOT actually land on-chain. A
        // network error AFTER a successful submit must keep the token spent, else
        // one paid token yields two on-chain sends.
        if (await txLanded(conn, transaction)) {
          await stub.fetch('https://do/commit');
          return json({ error: 'submit ambiguous, treat as sent' }, 502);
        }
        await stub.fetch('https://do/release');   // undo claim → token reusable
        return json({ error: 'submit failed' }, 502);
      }
    }

    // --- Fallback: KV spent-set (best-effort, eventually consistent) when the
    //     DO namespace isn't bound (e.g. a partial deploy). ---------------------
    const spentKey = `spent:${nonce}`;
    if (await env.QUOTA.get(spentKey)) return json({ error: 'token already spent' }, 409);
    if ((await reserveN(env, capKey, cap, 1, TTL_DAY_MS)) <= 0) {
      return json({ error: 'daily cap reached' }, 503);
    }
    try {
      transaction.partialSign(treasury);
      const raw = transaction.serialize();
      const conn = new Connection(env.RPC_URL, 'confirmed');
      const signature = await conn.sendRawTransaction(raw, { skipPreflight: false });
      await env.QUOTA.put(spentKey, '1', { expirationTtl: 60 * 60 * 24 * 90 });
      return json({ signature });
    } catch (e) {
      console.error('submit failed (token)', e);
      await refundCounter(env, capKey);
      return json({ error: 'submit failed' }, 502);
    }
  }

  // ---- Legacy account path: receipt + seed-account token (free & fallback). ---
  // Rate-limit this account token.
  if (!(await underRateLimit(env, account))) {
    return json({ error: 'rate limited' }, 429);
  }

  // Nickname registry: a discovery publish reserves the nickname to this account.
  if (nick) {
    const owner = await env.QUOTA.get(`nick:${nick}`);
    if (owner && owner !== account) return json({ error: 'nickname taken' }, 409);
  }

  // Verify entitlement + reserve one message of quota.
  const grant = await reserveMessage(env, account, jws);
  if (!grant.ok) return json({ error: 'quota exceeded' }, 402);

  // FREE-tier sybil ceiling: unauthenticated sends draw from a SEPARATE, much
  // lower global daily cap, so an attacker minting seed accounts can never spend
  // more than FREE_DAILY_CAP of the treasury per day. Reserved atomically.
  const freeCapKey = `freecap:${day}`;
  if (grant.tier === 'free') {
    const freeCap = parseInt(env.FREE_DAILY_CAP ?? '', 10) || DEFAULT_FREE_DAILY_CAP;
    if ((await reserveN(env, freeCapKey, freeCap, 1, TTL_DAY_MS)) <= 0) {
      await refundMessage(env, account);
      return json({ error: 'free tier busy, try later' }, 503);
    }
  }

  // Atomically reserve daily-cap headroom before submitting.
  if ((await reserveN(env, capKey, cap, 1, TTL_DAY_MS)) <= 0) {
    await refundMessage(env, account);
    if (grant.tier === 'free') await refundCounter(env, freeCapKey);
    return json({ error: 'daily cap reached' }, 503);
  }

  // Co-sign the fee-payer slot with the treasury and submit.
  try {
    transaction.partialSign(treasury); // fills the fee-payer signature slot
    const raw = transaction.serialize();
    const conn = new Connection(env.RPC_URL, 'confirmed');
    const signature = await conn.sendRawTransaction(raw, { skipPreflight: false });
    if (nick) {
      await env.QUOTA.put(`nick:${nick}`, account, { expirationTtl: 60 * 60 * 24 * 400 });
    }
    return json({ signature });
  } catch (e) {
    console.error('submit failed', e);
    await refundMessage(env, account);            // don't burn quota on submit failure
    await refundCounter(env, capKey);             // uncount the reserved daily slot
    if (grant.tier === 'free') await refundCounter(env, freeCapKey);
    return json({ error: 'submit failed' }, 502);
  }
}

/** Best-effort check whether a signed tx already landed (or is in flight) on
 *  chain — used to decide, after an ambiguous submit error, whether a paid token
 *  should stay spent. Returns false on any lookup failure (fail safe: reusable). */
async function txLanded(conn: Connection, transaction: Transaction): Promise<boolean> {
  try {
    if (!transaction.signature) return false;
    const sig = bs58.encode(transaction.signature);
    const st = await conn.getSignatureStatus(sig, { searchTransactionHistory: true });
    return !!st?.value; // any known status (processed/confirmed/finalized) counts
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------- /credit

async function handleCredit(req: Request, env: Env): Promise<Response> {
  const { jws, account } = await req.json<any>();
  if (!jws || !account) return json({ error: 'missing jws/account' }, 400);

  const claims = await verifyAppleJWS(jws, env);
  const messages = PACK_MESSAGES[claims.productId];
  if (!messages) return json({ error: 'not a pack product' }, 400);

  // Dedup the receipt ATOMICALLY: a raced get/put here lets N concurrent /credit
  // calls with ONE receipt each read "not seen" and all credit the pack — one
  // purchase inflated N×. claimOnce returns true only for the first caller.
  if (!(await claimOnce(env, `tx:${claims.transactionId}`, TTL_CREDIT_MS))) {
    return json({ ok: true, alreadyCredited: true });
  }
  const balance = await addBalance(env, `pack:${account}`, messages);
  return json({ ok: true, balance });
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

type Grant = { ok: boolean; tier: 'free' | 'sub' | 'pack' | null };

async function reserveMessage(env: Env, account: string, jws?: string): Promise<Grant> {
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
  const hasSub = allowance > 0;

  const month = new Date().toISOString().slice(0, 7);
  const usedKey = `used:${account}:${month}`;
  const effectiveAllowance = Math.max(allowance, FREE_MONTHLY);

  // Atomically reserve one message of the monthly allowance. reserveN grants only
  // while used < allowance inside a single serialized op, so a concurrent race
  // can't push an account past its quota.
  if ((await reserveN(env, usedKey, effectiveAllowance, 1, TTL_MONTH_MS)) > 0) {
    // Without an active subscription the message comes from the free allowance.
    return { ok: true, tier: hasSub ? 'sub' : 'free' };
  }

  // Allowance exhausted — draw from a purchased consumable pack (atomic spend).
  if (await spendBalance(env, `pack:${account}`)) {
    return { ok: true, tier: 'pack' };
  }
  return { ok: false, tier: null };
}

// ------------------------------------------------------ discovery nick parse

const MEMO_PROGRAM_ID = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
const DISCOVERY_PREFIX = 'PDIR1:';

/**
 * If this transaction is a discovery-registry publish, return the lowercased
 * nickname it claims; otherwise null. Ordinary messages carry an encrypted memo
 * that does not start with the discovery prefix, so they are ignored. Used to
 * enforce authoritative nickname uniqueness in KV.
 */
function extractDiscoveryNick(transaction: Transaction): string | null {
  for (const ix of transaction.instructions) {
    if (ix.programId.toBase58() !== MEMO_PROGRAM_ID) continue;
    let text: string;
    try {
      text = new TextDecoder().decode(ix.data);
    } catch {
      continue;
    }
    if (!text.startsWith(DISCOVERY_PREFIX)) continue;
    try {
      const rec = JSON.parse(text.slice(DISCOVERY_PREFIX.length));
      const n = String(rec?.nickname ?? '').trim().toLowerCase();
      return n || null;
    } catch {
      return null;
    }
  }
  return null;
}

async function refundMessage(env: Env, account: string): Promise<void> {
  const month = new Date().toISOString().slice(0, 7);
  await refundCounter(env, `used:${account}:${month}`);
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
  /** Stable across a subscription's renewals — the sybil anchor for issuance
   *  metering (a renewal or restore gives a NEW transactionId but the SAME
   *  originalTransactionId, so metering on this can't be farmed). */
  originalTransactionId: string;
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
    originalTransactionId: String(payload.originalTransactionId ?? payload.transactionId ?? ''),
    expiresDate: payload.expiresDate ? Number(payload.expiresDate) : undefined,
    bundleId: payload.bundleId ? String(payload.bundleId) : undefined,
  };
  // Fail CLOSED on app binding: when BUNDLE_ID is configured, a receipt with a
  // missing or mismatched bundleId is rejected — a valid Apple-signed JWS from a
  // different app must never satisfy our entitlement check.
  if (env.BUNDLE_ID && claims.bundleId !== env.BUNDLE_ID) {
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
