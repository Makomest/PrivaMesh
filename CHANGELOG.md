# Changelog

All notable changes to PrivaMesh are documented here. Versions match the App
Store release, and the format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Security work following ten external reports and two internal audits. The full
table, including what was fixed and what was documented instead, is in
[SECURITY.md](SECURITY.md).

### Fixed

- Relay: a caller could set the priority fee the treasury paid. Compute Budget
  instructions carry no accounts, so they passed the guard that checks whether
  the treasury is referenced. They are now parsed and held to server-side
  ceilings on units, price, and the product of the two.
- Relay: one blind token could buy a transaction per spelling of its nonce.
  Nonces are canonicalised before verification and before spending.
- Relay: one subscription could take a fresh monthly allowance per `account`
  value sent. The counter is keyed on Apple's `originalTransactionId`.
- Relay: the per-minute limiter was keyed on the same caller-chosen `account`.
  A verified subscription now throttles in its own bucket, and a throttled
  caller gets its reserved message back.
- Relay: a spent blind token became spendable again when the 90-day retention
  alarm deleted its record. Records are kept until tokens can carry an
  authenticated expiry.
- Relay: the declared Durable Objects had never been created, so the worker ran
  on the eventually-consistent KV fallback. Now `new_sqlite_classes`.
- iOS: the default `URLSession` shared the system cookie jar, which let a relay
  link a purchase at `/issue` to a send at `/send` without touching the blind
  signatures. The session now stores no cookies and no cache.
- iOS: the blind-token issuer key is pinned, so a relay cannot tag a client by
  serving it a distinctive modulus.
- iOS: an old session-opening message could be replayed as a new message.
  Contacts remember the digests of openers they have accepted.
- iOS: any funded wallet could take over a nickname in the on-chain registry.
  Ownership is decided by the chain, and every record must carry a wallet
  signature.
- iOS: the message store was not excluded from iCloud backup.
- iOS: the app switcher snapshot captured the open conversation. A cover is
  drawn at `.inactive`, before the snapshot is taken.
- iOS: the passcode could be changed into the duress code, silently disabling
  duress. Confirming a passcode in Settings no longer burns brute-force
  attempts.

### Changed

- Stealth-address reads are spread across the RPC pool by address, so no single
  node sees the whole conversation graph. This reduces the exposure; it does not
  remove it, and running your own node is still the answer.
- The nickname screen now says that reserving a handle writes it, the wallet
  address and the public key to a permanent public registry that anyone can
  list. It previously said only that contacts would see the nickname.

### Added

- A duress passcode: a second code that wipes the local store and signs out.
- A visible cooldown after repeated wrong passcode entries.
- Regression tests for every externally reported issue, in
  `relay/test/security-reports.test.mjs` and the iOS test target.

## [1.0] — 2026-08-06

First App Store release.

### Added

- End-to-end encrypted one-to-one messaging: X3DH handshake, Double Ratchet per
  message, AES-256-GCM for the payload.
- Post-quantum handshake on iOS 26: X-Wing, combining ML-KEM-768 with X25519.
  Falls back to the classical handshake when the recipient publishes no
  post-quantum prekey.
- Accounts derived from a BIP-39 recovery phrase generated on device. No phone
  number, no email, no account database.
- Stealth addressing: a fresh one-time address per message, derived from the
  shared root so only the two participants can compute it.
- Fixed padding buckets at 32, 64, 128, 256 and 512 bytes. The ceiling is set by
  Solana's 1232-byte transaction limit.
- Optional cover traffic emitting decoys at random 3–10 minute intervals.
  **Off by default**, because decoys spend from the message allowance.
- Anonymous payment using RSA blind signatures, so a send cannot be linked to a
  purchase or to another send.
- Wallet-signed prekey bundles published on-chain for MITM-resistant contact
  verification without a key directory.
- Keys stored in the iOS Keychain behind Face ID or Touch ID.

### Not shipped, despite appearing in earlier material

The v1 white paper PDF (now `PrivaMesh-WhitePaper-v1-OUTDATED-2026-06.pdf`)
described a self-custodial wallet, in-chat SOL transfers, gifting and an NFT
nickname marketplace. **None of that shipped in 1.0.** `MemoTransactionBuilder.sendSOL`
and `MessageSender.sendSOLNote` exist but have no callers, and
`MarketService.mintNickname` only appends to a local array. Treat WHITEPAPER.md
as the current description; the PDF describes a design that was cancelled.

### Known limitations at release

See https://privamesh.org/limitations. No independent security audit has been
completed. iPhone only, iOS 26.5 or later. No groups, files, calls or
multi-device sync. Message history cannot be recovered.

[1.0]: https://apps.apple.com/app/privamesh-messenger/id6785997584
