# Contributing to PrivaMesh

## Before you start

For anything security-sensitive, read [SECURITY.md](SECURITY.md) first and email
rather than opening an issue.

For everything else, open an issue before writing code. This is a small project
with a specific threat model, and a change that is technically fine can still be
wrong for the design — it is better to find that out in a paragraph than in a
pull request.

## Requirements

- Xcode with an iOS 26.5 SDK
- An iPhone or simulator running iOS 26.5 or later
- A funded devnet or mainnet account if you want to exercise sending

## Ground rules for cryptographic code

- **Do not invent primitives.** PrivaMesh composes X3DH, the Double Ratchet,
  AES-256-GCM and ML-KEM-768. Novel cryptography in a shipping messenger is a
  warning sign, not a feature.
- **Do not weaken a default to make something easier.** If a change makes the
  shipped configuration less private, it needs to be argued on its own terms and
  documented on the limitations page.
- **Anything that touches key derivation, the ratchet, padding or address
  derivation needs test vectors** covering the change.

## Pull requests

- One logical change per pull request.
- Explain *why* in the description, not just what — the diff already shows what.
- Note any effect on what the fee worker, the RPC provider or a chain observer
  can see. If a change alters that, say so explicitly; those claims are published
  and have to stay true.
- Update the relevant documentation in the same pull request.

## Claims and documentation

The website, this repository, the white paper and the App Store listing are all
supposed to describe the same system. If your change makes any of them wrong,
fixing them is part of the change.

Absolute claims are not acceptable in documentation. "No servers" is false —
there is a fee worker. Write what is checkable instead.
