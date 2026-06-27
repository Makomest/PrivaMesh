# PrivaMesh — Privacy Policy

_Last updated: 2026_

PrivaMesh is a **serverless** messenger. We do not operate any backend server, account database, or message store. This policy explains what that means for your data.

## Summary

- **We collect nothing.** PrivaMesh has no servers, no analytics, no tracking, no ads.
- Your messages, contacts, and keys are stored **only on your device**.
- Messages travel as **end-to-end encrypted** data on the public Solana blockchain. We cannot read them.
- We have no account for you, no email, no phone number — only a key pair you control.

## What we do NOT collect

PrivaMesh has **no first-party server**, so we do not — and technically cannot — collect, log, or store:

- Your messages or their content
- Your contacts or contact graph
- Your IP address
- Analytics, usage data, device identifiers, or advertising identifiers
- Email, phone number, name, or any personal identifier

We do not use third-party analytics, advertising, or tracking SDKs. See the app's `PrivacyInfo.xcprivacy` manifest.

## Data stored on your device only

The following never leaves your device and is never transmitted to us:

- Your **seed phrase** and cryptographic keys — stored in the iOS Keychain, optionally locked behind Face ID / passcode.
- **Decrypted messages, contacts, and chat history** — stored locally (SwiftData), removable at any time.
- App preferences (theme, language, notification settings).

Deleting the app removes this local data. Your on-chain history (encrypted) remains on the blockchain, undecryptable without your keys.

## Data on the public blockchain

PrivaMesh transports messages as encrypted memos inside Solana transactions. Therefore:

- The **encrypted ciphertext** of messages is publicly visible on the Solana ledger, but is unreadable without the recipient's keys.
- Transaction metadata (existence, timestamp, fee payer) is public, as with any blockchain. PrivaMesh mitigates this with one-time **stealth addresses**, optional **cover traffic**, and an optional separate **gas wallet**.
- This data is immutable and outside our control. We cannot delete it.

## Third parties

- **Solana RPC providers** — the app connects to a public Solana RPC endpoint (configurable, self-hostable) to read and submit transactions. That provider may observe your IP address and the requests you make, like any internet service. Use a VPN, Tor, or your own RPC for additional protection. We do not control or share data with these providers beyond ordinary network requests.
- **Apple** — subscription purchases (PrivaMesh+) are processed by Apple via StoreKit. Apple's privacy policy applies to that transaction. We receive no payment details.

## Encryption

Messages are end-to-end encrypted using the X3DH key-agreement protocol and the Double Ratchet (AES-256-GCM). Keys are generated and held on your device only.

## Children

PrivaMesh is not directed to children under 17.

## Changes

We may update this policy. Material changes will be reflected in the app and this page.

## Contact

Questions or reports: **privamesh@proton.me**
