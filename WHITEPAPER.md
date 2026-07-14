# PrivaMesh — White Paper

**A serverless, end-to-end encrypted messenger**

Version 2.0 · 2026

---

## Abstract

PrivaMesh is a **private, serverless messenger** with **no backend account database of its own**. Everything personal — identity, contacts, and message history — stays on the user's device. Coordination between devices happens over a public, decentralized, append-only transport that carries only ciphertext; there is no PrivaMesh account server and no operator who can read messages or reconstruct a social graph.

Messages are end-to-end encrypted with the X3DH key-agreement protocol and the Double Ratchet — the same family of protocols trusted by leading secure messengers. Identity, discovery, and delivery are expressed as self-authenticating events that any client can independently verify.

This paper describes the design goals, the cryptographic protocol, the delivery transport, the metadata-privacy layer (stealth addresses, cover traffic, disappearing messages), the serverless discovery mechanism, the membership model, and the explicit security trade-offs of the architecture.

---

## 1. Motivation

Mainstream messengers protect message *content* with end-to-end encryption but still centralize *everything else*: who talks to whom, when, contact graphs, account identifiers, and the servers that route every packet. That metadata is enough to deanonymize, censor, and coerce.

PrivaMesh starts from a different premise: **if there is no account server, there is nothing to subpoena, breach, or shut down.** The design question becomes "what can be expressed as a verifiable public event, and what must stay on the device?" Content and long-term secrets stay on the device; coordination happens over a neutral, permissionless transport.

---

## 2. Design Principles

1. **No first-party account servers.** The vendor operates no identity, message, or storage service that holds user data.
2. **End-to-end by default.** Plaintext never leaves the device. Keys never leave the device.
3. **Self-owned identity.** A single recovery phrase controls the account. No recovery backdoor.
4. **Verifiable, not trusted.** Discovery is a self-authenticating record the client checks cryptographically rather than accepting a server's word.
5. **Metadata minimization.** Beyond content, the app actively obscures *who*, *when*, and *how often* using stealth addresses and cover traffic.
6. **Forward secrecy over convenience.** Per-message ratcheting means a compromised device cannot decrypt past traffic (see §11).

---

## 3. System Architecture

PrivaMesh is a native iOS (SwiftUI) client. It has no first-party backend. Encrypted messages are delivered over a public, decentralized, append-only transport, reached through user-configurable, self-hostable endpoints with automatic rotation on failure.

```
                ┌──────────────────────────────┐
                │        PrivaMesh client       │
                │  (keys, plaintext, contacts)  │
                └───────────────┬──────────────┘
                                │ ciphertext only
                                ▼
                ┌──────────────────────────────┐
                │   decentralized transport      │
                │  • encrypted message envelopes │
                │  • self-authenticating registry│
                └──────────────────────────────┘
```

All durable *shared* state carries only ciphertext or signed public keys:

| Concern    | Representation                                                    |
|------------|------------------------------------------------------------------|
| Messages   | encrypted envelopes carried by the transport                     |
| Discovery  | signed prekey bundles posted to a self-authenticating registry   |

Everything else — contacts, decrypted messages, ratchet sessions, private keys — is local to the device and never transmitted.

---

## 4. Identity and Key Management

A PrivaMesh account is rooted in a standard recovery phrase (a BIP-39 mnemonic). It is an **account key**, not funds — a password-equivalent that lets a user restore their identity and contacts on a new device.

Messaging uses a set of Curve25519 keys — an identity key, a signed prekey, and ephemeral keys — generated with CryptoKit and stored in the iOS Keychain. These keys are **derived deterministically from the recovery phrase** via HKDF-SHA256 with domain-separated labels, so re-entering the phrase on any device reconstructs the same messaging identity — while a separate messaging salt keeps them cryptographically independent of every other key derived from the phrase. Keys are **keyed per account**, so multiple accounts on one device remain mutually unlinkable.

The recovery phrase can optionally be locked behind Face ID / passcode via a Keychain access-control list, without prompting on every use.

---

## 5. Messaging Protocol

PrivaMesh implements an asynchronous handshake and ratchet.

### 5.1 Session establishment — X3DH

The first message to a new contact carries a `sessionInit` envelope:

```
[0x01] [IK_A : 32B] [EK_A : 32B] [EncryptedMessage …]
```

The sender combines its identity key (IK_A) and a fresh ephemeral key (EK_A) with the recipient's published identity and signed-prekey to compute an X3DH shared secret. Because the envelope is self-contained, a recipient can decrypt a first message from a *stranger* without any prior contact record — enabling unsolicited "message requests" while keeping the protocol stateless on the network.

### 5.2 Ongoing messages — Double Ratchet

Once a session exists, every message advances a Double Ratchet:

- **KDF_RK** — `HKDF-SHA256(salt = root key, IKM = DH output, info = "PrivaMesh-DR-RK")`
- **KDF_CK** — `HMAC-SHA256` chain step
- **Encryption** — `AES-256-GCM`, with the 40-byte ratchet header bound as Associated Data

The wire format of an encrypted message is:

```
[0..32)  sender ratchet public key
[32..40) message counters (Ns, PN)
[40..]   AES-GCM combined  (12-byte nonce ‖ ciphertext ‖ 16-byte tag)
```

Each message uses a fresh chain key, so compromising one key never exposes earlier or later messages (forward secrecy + post-compromise security).

### 5.3 Application payload

Inside the encrypted channel, a typed payload distinguishes message kinds: `text` and `cover` (decoy — see §6.2). Padding is applied before encryption so ciphertext length does not reveal message length. The payload also piggybacks the sender's current nickname, so contacts auto-update without a profile server.

### 5.4 Transport

The encrypted envelope is delivered over the decentralized transport as an opaque ciphertext blob. The recipient discovers it by scanning their inbox address and per-conversation stealth addresses (§6.1). Envelopes carry no value — only ciphertext. Delivery and infrastructure costs are covered by the developer, not the user (see §9); the user never buys, holds, or spends any cryptocurrency, and there is no wallet in the app.

---

## 6. Metadata Privacy

End-to-end encryption hides content. PrivaMesh adds independent layers to hide the metadata a public transport would otherwise expose.

### 6.1 Stealth addresses

If every message to a contact landed on the same inbox address, an observer could reconstruct the conversation graph and frequency. Instead, each conversation derives a **one-time address per message** from the X3DH shared secret using a deterministic chain (`StealthAddress.address(root, label, index)`). Both parties can compute the next address; an outside observer sees unrelated, single-use addresses with no visible link to either participant.

### 6.2 Cover traffic

Conversation *timing* is itself metadata. With cover traffic enabled, the client sends decoy messages (`kind = cover`) at randomized intervals to real contacts. Decoys are full, valid encrypted messages that advance the ratchet and are silently dropped on receipt — indistinguishable from real traffic. This breaks timing correlation. It is opt-in.

### 6.3 Disappearing messages

Per-contact, the client can auto-purge decrypted copies after a chosen interval. This is a *local* control over plaintext retention; the transported ciphertext remains undecryptable to anyone without the ratchet state.

---

## 7. Serverless Discovery

To message someone by a human-readable nickname without a directory server, PrivaMesh uses a **self-authenticating registry**. A user publishes a prekey bundle — the keys needed to start an X3DH session — to a well-known registry, indexed by nickname.

The critical anti-MITM property: the published bundle is **signed**. The signature ties the messaging keys to the identity that posted them, so a third party cannot inject a forged bundle for a nickname they do not control. Clients verify the signature before trusting any discovered bundle. This replaces a trusted key server with a publicly auditable, self-authenticating record.

---

## 8. Multi-Account

A device can hold several fully independent accounts, each with its own recovery phrase, nickname, chats, and messaging identity. Because messaging keys are keyed per account, accounts are mutually unlinkable; switching accounts re-scopes the entire app. Accounts can be created fresh or restored by recovery phrase.

---

## 9. Membership

Messaging is metered with a small free monthly allowance. **PrivaMesh+** unlocks a higher monthly message allowance and a verification badge; consumable message packs are also available. Access is sold exclusively through Apple StoreKit 2 in-app purchase, as App Store policy requires for digital services. In-app purchases grant only a message allowance and membership perks — no cryptocurrency, token, or digital asset is ever sold, and all delivery costs are covered by the developer.

---

## 10. Security Model and Trade-offs

**What an adversary cannot do.** Without the device's keys, no party — including the vendor — can read message content or forge a discovered identity (signatures are verified). There is no central store to breach.

**What remains visible.** The transport is public. Message existence and timing (mitigated by cover traffic) are observable to a global passive adversary. Stealth addresses unlink the recipient graph but do not hide that *some* message occurred. Anonymity therefore depends on using the privacy layers.

**Forward secrecy vs. recoverability.** The messaging *identity* is derived from the recovery phrase, so restoring the phrase on a new device recovers the account, contacts, and provable presence to peers. Ratchet *session state*, however, is ephemeral and device-local — so past message plaintext is **not** recoverable from the phrase alone. The transported ciphertext exists but is undecryptable without the original ratchet state. This is a deliberate trade-off that preserves forward secrecy: a stolen phrase cannot unlock a user's past conversations. An optional encrypted device backup would reverse it at the cost of weaker forward secrecy.

**Local device security.** Since the device holds everything, the recovery phrase can be locked behind biometrics/passcode, and a full wipe erases all account keys, per-account messaging identities, contacts, and chats.

**Known limitations.** Availability depends on the public transport infrastructure; transport endpoints can observe a user's read queries (mitigated by rotation and the option to self-host).

---

## 11. Conclusion

PrivaMesh demonstrates that a private messenger can run with **no first-party account server**. By expressing coordination as verifiable, self-authenticating events and keeping content and secrets on the device, it removes the operator from the trust model entirely: there is no one to ask for your messages, because no one has them. The cost of that posture — metadata that must be actively obscured rather than hidden by a trusted middleman — is made explicit rather than hidden. For users who would rather trust mathematics than a company, that is the right trade.

---

*This document describes the system as implemented.*
