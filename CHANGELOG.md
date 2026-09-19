# Changelog

All notable changes to PrivaMesh are documented here. Versions match the App
Store release, and the format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Security work following twelve external reports and two internal audits. The full
table, including what was fixed and what was documented instead, is in
[SECURITY.md](SECURITY.md).

### Fixed

- iOS: every stranger's first message landed in the same conversation. The
  sender was read from the transaction's fee payer, which on the sponsored path
  is the shared treasury rather than the sender - by design, since the sender's
  own address never reaches the chain. Distinct message requests therefore
  merged into one contact, each new opener replaced its ratchet and stealth
  root, and a reply written to one stranger was encrypted to the latest one and
  sent to a stealth address only that stranger polls. Senders are now matched on
  the identity key in the envelope, and a fee payer counts as the sender only
  when it also signed the memo.
- Relay: any certificate chaining to Apple Root CA - G3 was accepted as an App
  Store receipt signer. That root also anchors Apple Pay merchant certificates
  and ordinary developer signing certificates, whose private keys their holders
  keep, so a caller could sign their own receipt and take PRO, unlimited message
  packs and unlimited blind tokens at the treasury's expense. The leaf must now
  carry Apple's receipt-signing marker OID and the intermediate the WWDR App
  Store one, and an end-entity certificate can no longer stand in for the
  intermediate.
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
- iOS: the relay could turn anonymity off for everyone by declining to take part
  in it. Whenever no token could be spent — `/pubkey` answering
  `enabled: false`, or `/send` rejecting the token it was handed — the client
  re-sent the same message with the Apple receipt attached, which is the
  purchase-to-send link the blind signatures exist to break, obtained without
  touching the signatures. A device that should have a token — it has been
  served an issuer key, and StoreKit says the subscription that pays for tokens
  is active — now keeps the token path or reports a failed send. A device that
  should not, because it has never seen a key or is on the free tier the relay
  meters per account, still takes the receipt path: it has no anonymity to lose
  there, and refusing would only stop it sending. Entitlement is read from
  StoreKit and not from the relay's answer, so the relay cannot claim the
  subscription is gone to get the receipt back.
- iOS: an old session-opening message could be replayed as a new message.
  Contacts remember the digests of openers they have accepted.
- iOS: any funded wallet could take over a nickname in the on-chain registry.
  Ownership is decided by the chain, and every record must carry a wallet
  signature.
- iOS: the message store was not excluded from iCloud backup.
- iOS: the app switcher snapshot captured the open conversation. A cover is
  drawn at `.inactive`, before the snapshot is taken.
- iOS: a post-quantum session opener starts with the same byte (0x02) as a Saved
  Messages memo, and both arrive on the account's real address. The dispatcher
  routed on the byte, so every PQ opener failed to authenticate under the
  self-encryption key and was dropped by a silent catch: adding a contact by QR
  or invite link between two PQ-capable devices produced no contact, no message
  request and no error. Which one it is is now decided by the key, not the byte.
- iOS: the passcode could be changed into the duress code, silently disabling
  duress. Confirming a passcode in Settings no longer burns brute-force
  attempts.
- iOS: the duress code deleted the chats and the active account slot, but left
  every account's seed phrase, messaging identity, relay token and gas-wallet key
  in the Keychain and the account list in UserDefaults — so the app's own account
  switcher could turn a "wiped" device back on. Duress and the manual reset now
  run the same wipe, and it clears the Keychain by service rather than by a list
  of key names, which per-account items (named after the wallet address) could
  never be complete in.
- iOS: deleted messages stayed readable in the store's write-ahead log after a
  wipe. The wipe now checkpoints, vacuums and checkpoints again, and a test scans
  the store files for message text.
- iOS: a wiped app opened on Welcome while a never-launched one opens on the
  onboarding slides, and delivered notifications (which name the sender) stayed
  in Notification Center. Both are cleared, so the wipe leaves nothing that says
  a wipe happened.
- iOS: wiping a busy account took about six seconds on the main thread — a freeze
  in place of the instant, silent wipe the feature promises. The messages were
  being deleted one object at a time because a batch delete of `ChatMessage` is
  refused outright (its `contact` inverse is mandatory); deleting the contacts
  instead lets the cascade take every message with them, in ~0.03s for 5,000.
- iOS: the brute-force cooldown also refused the duress code, so five wrong
  guesses by whoever held the phone disabled the wipe for up to an hour. The
  duress code is now answered during a cooldown; the passcode still is not.
- iOS: changing the passcode drops the duress code (it is stored under the
  passcode's salt) and said nothing. The change now ends on a notice, and the
  duress screen lists it.
- iOS: an unreadable Keychain made Settings report that a duress code was set.

### Changed

- The relay's blind-token issuer key is documented as required rather than
  optional. Left unset, `/issue` returns 501, `/pubkey` reports `enabled: false`
  and every send carries the Apple receipt — the link the tokens exist to break.
  `relay/README.md` and `wrangler.toml` now say so, with the `/pubkey` check to
  confirm a deployment.
- Stealth-address reads are spread across the RPC pool by address, so no single
  node sees the whole conversation graph. This reduces the exposure; it does not
  remove it, and running your own node is still the answer.
- The nickname screen now says that reserving a handle writes it, the wallet
  address and the public key to a permanent public registry that anyone can
  list. It previously said only that contacts would see the nickname.

### Added

- A duress passcode: a second code that wipes the local store and signs out.
- An onboarding slide for the duress code, in Russian and English: what the
  second code does, where to set it, and that the chain is not erased with it.
- A visible cooldown after repeated wrong passcode entries.
- Regression tests for every externally reported issue, in
  `relay/test/security-reports.test.mjs` and the iOS test target — including
  `RelayDowngradeTests`, `SenderAttributionTests`, `SelfMemoCollisionTests` and
  `DuressWipeTests`.

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
