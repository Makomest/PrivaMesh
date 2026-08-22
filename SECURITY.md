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

**Already-documented issues are not eligible** — see
https://privamesh.org/limitations. That includes the session-opening message
being recoverable from the recovery phrase, the absence of user-facing key
verification, cover traffic being off by default, permanent on-chain ciphertext,
and the RPC provider seeing your IP.

Full tiers, scope and exclusions: https://privamesh.org/bug-bounty

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
