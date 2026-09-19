# PrivaMesh Relay

Serverless (Cloudflare Worker) relay that lets PrivaMesh pay Solana network fees
for users, so no one in the app ever holds or spends cryptocurrency. Access is
metered by Apple IAP.

## What it does

- `POST /send` — receives a message transaction whose **fee payer is the app
  treasury** and which is already partial-signed by the sender. Verifies the
  user's Apple entitlement (JWS) and remaining quota, co-signs the fee-payer slot
  with the treasury key, submits to Solana, and returns the signature.
- `POST /credit` — verifies a consumable message-pack receipt and adds its
  messages to the account's quota balance (idempotent).

Quota lives in Workers KV and is **authoritative** — the app's on-device counter
is only a UX mirror. Never let the relay co-sign without a valid, unspent receipt.

## One-time setup

1. **Create the treasury wallet** (a fresh Solana keypair you fund):
   ```
   solana-keygen new --outfile treasury.json
   solana address -k treasury.json          # → put in the app's RelayConfig.treasuryPubkey
   ```
   Export its base58 secret for the Worker secret below. Fund it with SOL; keep a
   45-day buffer and monitor the balance.

2. **Install + create KV:**
   ```
   npm install
   npx wrangler kv namespace create QUOTA   # paste the id into wrangler.toml
   ```

3. **Set secrets:**
   ```
   npx wrangler secret put TREASURY_SECRET   # base58 64-byte secret key
   ```

4. **Set the blind-token issuer key.** This is not optional for a deployment
   that claims sends are unlinkable to a purchase:
   ```
   npm run keygen                            # prints TOKEN_RSA_N / _E / _D
   npx wrangler secret put TOKEN_RSA_N       # public modulus
   npx wrangler secret put TOKEN_RSA_D       # SIGNING SECRET — never commit
   ```
   With any of the three unset, `/issue` returns 501, `GET /pubkey` returns
   `{"enabled":false}`, and **every /send carries the Apple receipt** — so the
   relay sees the purchase, the recipient and the timing of every message. That
   is the legacy path, and it is the opposite of what the architecture page
   promises. Check it after deploying:
   ```
   curl -s https://<your-worker>/pubkey      # must be {"enabled":true, ...}
   ```
   Rotating the key invalidates outstanding tokens (clients re-issue) and is
   refused by clients that have pinned the old one — see BlindTokenService.

5. **Configure `wrangler.toml`:** RPC_URL (use a paid RPC in prod), BUNDLE_ID,
   PLUS_MONTHLY / PRO_MONTHLY (must match the app's tier caps).

6. **Deploy:**
   ```
   npx wrangler deploy
   ```
   Put the resulting URL into the app's `RelayConfig.baseURL`.

## App side

Fill in `privamesh/Core/RelayService.swift → RelayConfig`:
```swift
static let baseURL = "https://privamesh-relay.<subdomain>.workers.dev"
static let treasuryPubkey = "<treasury address>"
```

## Security notes / TODO before production

- ~~**Pin the Apple cert chain.**~~ Done. `verifyAppleJWS` walks the x5c chain to
  Apple Root CA - G3 *and* requires Apple's marker OIDs — receipt signing on the
  leaf, WWDR App Store on the intermediate. The root pin alone was not enough:
  it also anchors Apple Pay merchant and developer certificates whose private
  keys third parties hold. Consider moving to Apple's `app-store-server-library`
  if it ever ships a Workers-compatible build.
- **Rate-limit** per account token (e.g. max N/sec) to blunt abuse and protect
  the treasury even within quota.
- **Dynamic priority fee**: set compute-unit price from current network
  conditions instead of a fixed value, to keep landing cheap.
- **Alerting**: watch the treasury balance; auto-top-up or page when < 20%.
- **Reinstall abuse**: the free tier is keyed to the device account token, which
  resets on reinstall. For stronger protection, bind the token to Apple's
  `appAccountToken` / DeviceCheck.
