# Changelog

All notable changes to PrivaMesh are documented here. Versions match the App
Store release, and the format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
