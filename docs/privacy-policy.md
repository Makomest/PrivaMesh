# PrivaMesh — Privacy Policy

_Last updated: 2026_

PrivaMesh is a private, end-to-end encrypted messenger. Your messages, contacts,
and keys stay on your device; message content is never readable by us or anyone
else. To pay network delivery fees on your behalf (so you never need to hold
cryptocurrency), the app uses a small **fee relay** service. This policy explains
exactly what that service receives and what it does not.

## Summary

- **We cannot read your messages.** They are end-to-end encrypted; keys stay on your device.
- **No name, email, or phone number.** Your identity is a key pair you control.
- **No analytics, ads, or tracking SDKs.**
- A **fee relay** pays network fees for you and enforces your purchased message allowance. It receives the minimum needed to do that (see below) and never message content.

## What we do NOT collect

- Your messages or their content (they are end-to-end encrypted; we cannot decrypt them)
- Your contacts or contact graph
- Your name, email, phone number, or precise location
- Analytics, usage profiling, or advertising identifiers
- Your account keys or recovery phrase

We do not use third-party analytics, advertising, or tracking SDKs. See the app's
`PrivacyInfo.xcprivacy` manifest.

## Data stored on your device only

The following never leaves your device:

- Your **recovery phrase** and cryptographic keys — stored in the iOS Keychain, optionally locked behind Face ID / Touch ID / passcode.
- **Decrypted messages, contacts, and chat history** — stored locally (SwiftData), removable at any time.
- App preferences (theme, language, notifications).

Deleting the app removes this local data. Encrypted on the transport history remains on
the public transport, undecryptable without your keys.

## The fee relay (message sponsorship)

Every message is a message on a decentralized transport that carries a small network fee. So that
you never have to buy or hold cryptocurrency, PrivaMesh operates a **fee relay**
that pays those fees from an app-funded account and enforces the message allowance
you obtained through Apple In-App Purchase. When you send a message, mint a
nickname, or publish your profile to search, the app contacts the relay. The
relay receives:

- **The transaction to co-sign** — it contains only the *encrypted* message payload (the relay cannot read it), a one-time **stealth** recipient address, and a fresh **ephemeral** sender key. Your real account address is never in it.
- **Your device's IP address** — as with any network request. It is used only to route the request and is not stored to build a profile of you.
- **Your Apple purchase receipt (JWS)** — to verify you have an active PrivaMesh+ subscription or message pack. Verification is cryptographic; we receive no card or payment details.
- **A per-account token** — used to count your remaining message allowance. It is not your name, account address, or Apple ID, and is not linked to your identity.

The relay stores only **quota counters** (how many messages remain), keyed by that
token, in order to enforce your allowance and protect the shared delivery account from abuse. It does **not** store message content (it cannot read it) and
does not sell or share any of this data.

## Data on the public decentralized transport

PrivaMesh transports messages as encrypted memos inside messages on a decentralized transport:

- The **encrypted ciphertext** is publicly visible on the public transport but is unreadable without the recipient's keys.
- Transaction metadata (existence, timestamp, fee payer) is public, as on any decentralized transport. PrivaMesh reduces linkability with one-time **stealth addresses**, **ephemeral** per-message signers, an app-paid fee payer (your address never appears), and optional **cover traffic**.
- This data is immutable and outside our control. We cannot delete it.

## Third parties

- **Network transport provider** — the app and relay connect to a transport endpoint to read and submit transactions. That provider may observe request metadata (including IP) like any internet service.
- **Cloudflare** — the fee relay runs on Cloudflare's serverless platform, which processes requests on our behalf.
- **Apple** — In-App Purchases (PrivaMesh+ and message packs) are processed by Apple via StoreKit. Apple's privacy policy applies. We receive no payment details.

## Encryption

Messages are end-to-end encrypted using the X3DH key-agreement protocol and the
Double Ratchet (AES-256-GCM). Keys are generated and held on your device only.

## Children

PrivaMesh is not directed to children. An age rating of 16+ applies.

## Changes

We may update this policy. Material changes will be reflected in the app and on
this page.

## Contact

Questions or reports: **privamesh@proton.me**
