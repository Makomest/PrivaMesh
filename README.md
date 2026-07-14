<div align="center">

<img src=".github/assets/logo.png" width="120" alt="PrivaMesh logo" />

# PrivaMesh

**A serverless, end-to-end encrypted messenger.**

*Trust math, not companies.*

![Platform](https://img.shields.io/badge/platform-iOS-black)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![E2E](https://img.shields.io/badge/encryption-X3DH%20%2B%20Double%20Ratchet-blue)

**[privamesh.org](https://privamesh.org)**

</div>

---

PrivaMesh is a private messenger built for people who don't want their conversations logged, mined, or sold. **No phone number. No email. No profile.** You sign up with nothing — your identity is a key generated on your device. Everything personal — your identity, contacts, and chat history — stays local to your phone and is protected by the iOS Keychain. Your keys never leave your device.

## Screenshots

<div align="center">

<img src=".github/assets/screenshots/01.png" width="30%" alt="Private by default" />
<img src=".github/assets/screenshots/02.png" width="30%" alt="No servers" />
<img src=".github/assets/screenshots/03.png" width="30%" alt="Hide who, when, how" />

<img src=".github/assets/screenshots/04.png" width="30%" alt="No phone, no email" />
<img src=".github/assets/screenshots/05.png" width="30%" alt="End-to-end encrypted" />
<img src=".github/assets/screenshots/06.png" width="30%" alt="Own your identity" />

</div>

## Private by design

Everything private is local to the device. There is no account database and nothing about you to leak.

| What | Where it lives |
|------|----------------|
| Identity, contacts, chat history | **your device only** — SwiftData + Keychain, never transmitted |
| Private keys & recovery phrase | **your device only** — iOS Keychain, device-only, biometric-lockable |
| Message delivery | a decentralized, serverless transport carrying only ciphertext |

Sign up with nothing at all — no phone number, no email, no personal data. Your identity is a key you own, stored in the iOS Keychain and lockable with Face ID / Touch ID.

## Encryption

The cryptographic core is a well-established design: **X3DH** for the asynchronous handshake, the **Double Ratchet** for ongoing messages — the same family of protocols trusted by the world's leading secure messengers.

- **Key agreement** — X3DH over Curve25519. The first message is self-contained (carries the sender's identity + ephemeral keys), so a recipient can decrypt a first message without any prior server-stored state.
- **Per-message keys** — Double Ratchet: `KDF_RK = HKDF-SHA256`, `KDF_CK = HMAC-SHA256`, payload sealed with `AES-256-GCM` (the ratchet header is bound as Associated Data). A fresh key per message → **forward secrecy** and post-compromise security.
- **Padding** — plaintext is padded to fixed buckets before encryption, so ciphertext length doesn't leak message length.

> Code: [`Core/PrekeyBundle.swift`](privamesh/Core/PrekeyBundle.swift) (X3DH), [`Core/DoubleRatchet.swift`](privamesh/Core/DoubleRatchet.swift), [`Core/CryptoBox.swift`](privamesh/Core/CryptoBox.swift).

## Metadata privacy

End-to-end encryption hides *content*. PrivaMesh adds independent layers to also hide **who**, **when**, and **how**.

- **Stealth addresses** — each conversation derives a one-time delivery address per message from the X3DH shared secret, so an outside observer sees unrelated single-use addresses with no visible link to either participant.
- **Cover traffic (opt-in)** — the client can emit decoy messages at randomized intervals — full, valid encrypted messages that advance the ratchet and are silently dropped on receipt — breaking timing correlation.
- **Unlinkable accounts** — messaging keys are generated per account and stored device-only; multiple accounts on one device are cryptographically unlinkable.

## Anti-MITM discovery

Finding someone by nickname uses a **self-authenticating registry** instead of a trusted key server. A published prekey bundle is signed so its messaging keys are tied to the identity that posted them; a client verifies the signature before trusting any discovered bundle, so nobody can inject a forged identity for a nickname they don't control.

> Code: [`Core/OnChainDiscovery.swift`](privamesh/Core/OnChainDiscovery.swift), [`Core/PollingService.swift`](privamesh/Core/PollingService.swift).

## Security model

**What an adversary cannot do.** Without your device keys, no party can read message content or forge a discovered identity (signatures are verified). There is no central store to breach.

**Forward secrecy.** Messaging keys and ratchet sessions are random and device-local. This delivers forward secrecy and deniability — and means restoring an account from its recovery phrase recovers your **identity and contacts**, not past message plaintext (that stays undecryptable without the original ratchet state). A deliberate trade-off, matching comparable secure messengers.

## Membership

Messaging is metered with a small free monthly allowance. **PrivaMesh+** (optional, via Apple In-App Purchase) unlocks a higher monthly message allowance and a verification badge; consumable message packs are also available. All delivery and infrastructure costs are covered by us, the developer — users never buy, hold, or spend any cryptocurrency, and there is no wallet in the app.

## Tech

- **SwiftUI** + SwiftData, iOS 17+
- **CryptoKit** — Curve25519 X3DH, HKDF/HMAC-SHA256, AES-256-GCM; TweetNacl for ed25519 signatures
- iOS **Keychain** (device-only, biometric-lockable) for the recovery phrase + messaging keys

```bash
open privamesh.xcodeproj   # scheme: privamesh → run on device/simulator
```

> Never commit private keys or API secrets.

---

<div align="center">
<sub>Describes the system as implemented.</sub>
</div>
