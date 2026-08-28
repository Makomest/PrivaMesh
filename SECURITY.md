# Security Policy

## Audit status

**Independent security audit: not completed yet.**

PrivaMesh builds on well-studied primitives — X3DH, the Double Ratchet,
AES-256-GCM, and ML-KEM-768 (via X-Wing) on iOS 26. Those are proven. This
implementation of them has not been reviewed by a qualified third party.

The source is public so it can be audited. Until someone has, treat the
project's security claims as unverified. When an audit is completed, this file
and https://privamesh.org/security will carry the auditor, the report, the app
version and the exact commit that was reviewed.

## Supported versions

| Version | Supported |
| ------- | --------- |
| 1.0     | Yes       |

PrivaMesh requires iOS 26.5 or later and has shipped one major version, so there
is no older branch to backport to. When that changes, the supported window will
be stated here rather than implied.

## Reporting a vulnerability

Email **privamesh@proton.me** with `security` in the subject line.

Please include:

- the app version, your device model and your iOS version
- enough detail to reproduce the issue
- what you believe the impact is

**Never include your recovery phrase.** We will never ask for it, for any
reason, in any context. Anyone who does is trying to steal the account.

Do not open a public GitHub issue for a vulnerability.

## What we commit to

- **Acknowledgement within 2 business days.** If you do not hear back, assume
  the mail was lost and send it again.
- **A fix or a plan within 30 days** for anything that lets someone read
  messages, impersonate an account, or link a user to their activity.
- **Credit if you want it, silence if you do not.** We will not name you without
  asking first.
- **No legal threats** for good-faith research that does not target other
  people's accounts or data.

## Rewards

Confirmed findings are paid:

| Severity | Reward | Breaks |
| -------- | ------ | ------ |
| Critical | $500   | Reading plaintext without device keys, account impersonation, linking sender to recipient from public data, debiting the treasury |
| High     | $200   | Linking a purchase to a send, double-spending a blind token, recovering ratcheted history from the phrase |
| Medium   | $75    | Metadata leak beyond what is documented, quota or rate-limit bypass at scale |
| Low      | $25    | Crashes or contained information disclosure |

Payment happens on confirmation, not on fix. Duplicates go to whoever reported
first.

**Already-documented issues are not eligible**. See
https://privamesh.org/limitations. That includes the session-opening message
being recoverable from the recovery phrase, the absence of user-facing key
verification, cover traffic being off by default, permanent on-chain ciphertext,
and the RPC provider seeing your IP.

Full tiers, scope and exclusions: https://privamesh.org/bug-bounty

## Already reported and fixed

This list exists so nobody spends their time re-reporting something that is
already closed. Every entry below was reported, confirmed, and fixed in this
repository. **These are duplicates and are not eligible.** If you find a way
around one of these fixes, that is a new finding and we want it.

Reported by Mudit (mudit.raj32@gmail.com), August 2026:

| Issue | Status | Fixed in |
| ----- | ------ | -------- |
| Caller chose the priority fee the treasury paid, via Compute Budget instructions that carry no accounts and so passed the treasury-reference guard | Fixed | `e0a462b` |
| One blind token bought a transaction per spelling of its nonce, because the signature covers decoded bytes and the spent record was keyed by the string | Fixed | `e0a462b` |
| One subscription got a fresh monthly allowance per `account` value sent, because the quota counter was keyed on that unsigned field | Fixed | `e0a462b` |
| The per-minute rate limiter was keyed on the same caller-chosen `account`, so rotating it rotated the throttle | Fixed | `4d18125` |
| A default `URLSession` shared the system cookie jar, so a relay could set a cookie at `/issue` and read it at `/send`, linking a purchase to a send with the blind signatures untouched | Fixed | `47a5c80` |
| The client accepted any structurally valid issuer key, letting a relay tag one client by the modulus it was served | Fixed | `47a5c80` |
| A spent blind token became spendable again after the 90-day retention alarm deleted its record, while its signature stayed valid | Fixed | `47a5c80` |
| An old session-opening message could be replayed as a new message, because replay detection used the transaction signature and a copy changes it | Fixed | `e0a462b` |
| Any funded wallet could take over a nickname in the on-chain registry, because the winner was chosen by a timestamp the publisher writes | Fixed | `e0a462b` |

Found in our own audits and listed here for the same reason:

| Issue | Status | Fixed in |
| ----- | ------ | -------- |
| The message store was not excluded from iCloud backup | Fixed | `989611f` |
| The app switcher snapshot captured the open conversation | Fixed | `989611f` |
| One RPC node saw every stealth address a user watches, which is the conversation graph | Reduced, not closed. Reads are spread across the pool by address; the node asked still sees what it was asked | `989611f` |
| The passcode could be changed into the duress code, silently disabling duress | Fixed | `98b4128` |
| Confirming a passcode in Settings burned brute-force throttle attempts, so a mistype could lock you out of your own unlocked app | Fixed | `98b4128` |
| Durable Objects had never been created, so the relay ran on the eventually-consistent KV fallback that the single-spend code exists to avoid | Fixed | `6e342ef` |

Reported and **not** fixed, documented instead. These are known limitations, not
findings:

- A stolen recovery phrase decrypts the opening message and every message the
  sender sent before the first reply. Closing it needs one-time prekeys or a
  rotating non-deterministic signed prekey, and both mean a restored phrase can
  no longer open sessions started against the old published bundle.
- A published handle plus the opening message identifies both ends of a new
  conversation from public data. Removing that join is a wire-format change that
  older installs cannot read, so it needs a capability flag and a transition.
- The public registry is plaintext and enumerable: every published handle,
  wallet address and prekey bundle can be listed with one RPC call, permanently.
  Publishing a handle is optional and the app now says what it costs.

## Relay state you should know before testing

Blind tokens are **not enabled in production**: `TOKEN_RSA_N` is unset and
`/pubkey` returns `{"enabled":false}`. Findings in the blind-token code are still
real defects in this repository and are still paid, but they were not
exploitable against the live relay. The legacy receipt-plus-account `/send` path
is the one in service.

Please do not test against the production relay. Source-level and local
reproductions are enough, and are what we ask for.

## Scope

In scope:

- the iOS client in this repository
- the on-chain protocol (stealth address derivation, prekey bundles, padding)
- the fee worker described at https://privamesh.org/architecture

Out of scope, though we still want to hear about it:

- Solana itself and third-party RPC providers
- Apple platform issues
- social engineering of users or the maintainer

## Known limitations

These are documented rather than treated as findings. The full list is at
https://privamesh.org/limitations — the highlights:

- ciphertext written to a public chain is permanent
- transaction timing is visible unless cover traffic is enabled, and it is off
  by default
- padding reveals which size bucket a message fell into
- the RPC provider sees your IP address
- message history cannot be recovered after a reinstall, by design
