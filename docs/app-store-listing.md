# PrivaMesh — App Store Listing & Review Notes

Copy-paste fields for App Store Connect. Position the app as a **private messenger** first.

---

## App name
`PrivaMesh`

## Subtitle (max 30 chars)
- EN: `Serverless private messenger`
- RU: `Приватный мессенджер`

## Category
- Primary: **Social Networking**
- Secondary: Utilities

## Age rating
**17+** (unrestricted user-generated content / messaging)

## Promotional text (max 170 chars)
- EN: `A private, end-to-end encrypted messenger with no servers. Your messages live on-chain, your keys never leave your device.`
- RU: `Приватный мессенджер со сквозным шифрованием и без серверов. Сообщения — на блокчейне, ключи не покидают устройство.`

## Keywords (max 100 chars, comma-separated, no spaces)
- EN: `private,messenger,encrypted,e2ee,secure,chat,anonymous,web3,solana,serverless,no phone,privacy`
- RU: `мессенджер,приватный,шифрование,анонимный,безопасный,чат,web3,solana,без телефона,приватность`

---

## Description (EN)

PrivaMesh is a private messenger with no servers. It talks only to the public Solana blockchain — there is no PrivaMesh server, no message relay, no account database, and no operator who can read your messages or correlate your accounts.

Your messages are end-to-end encrypted (X3DH + Double Ratchet, the modern standard) and travel as encrypted data on-chain. Your keys never leave your device. No phone number, no email — just a key pair you control.

WHY PRIVAMESH
• No servers — nothing to subpoena, breach, log, or shut down
• End-to-end encryption — a fresh key for every message (forward secrecy)
• No phone or email — your identity is a seed phrase you alone hold
• Metadata privacy — one-time stealth addresses, optional decoy traffic, and a separate fee wallet keep who/when/how hidden
• Censorship-resistant — to block you, one would have to block the entire blockchain
• Open and verifiable — every shared event is a public, auditable on-chain record

Each account is a self-custodial key pair, so PrivaMesh also includes a lightweight SOL wallet for in-chat payments and gifts, plus on-chain NFT avatars and nicknames. These are secondary to the core product: private messaging.

PrivaMesh runs on Solana mainnet. Network actions cost small SOL fees. PrivaMesh is not a cryptocurrency exchange — it only sends and receives SOL between addresses you control.

Trust math, not companies.

## Description (RU)

PrivaMesh — приватный мессенджер без серверов. Приложение общается только с публичным блокчейном Solana: нет сервера PrivaMesh, нет ретранслятора сообщений, нет базы аккаунтов и нет оператора, который мог бы прочитать твою переписку или связать твои аккаунты.

Сообщения зашифрованы сквозным шифрованием (X3DH + Double Ratchet) и передаются зашифрованными на блокчейне. Ключи не покидают устройство. Без телефона и email — только ключ, который контролируешь ты.

ПОЧЕМУ PRIVAMESH
• Без серверов — нечего взломать, изъять, залогировать или выключить
• Сквозное шифрование — новый ключ на каждое сообщение (forward secrecy)
• Без телефона и email — твоя личность это seed-фраза, она только у тебя
• Приватность метаданных — одноразовые stealth-адреса, маскирующий трафик и отдельный кошелёк для комиссий скрывают кто/когда/как
• Устойчивость к цензуре — чтобы тебя заблокировать, надо заблокировать весь блокчейн
• Открыто и проверяемо — каждое общее событие это публичная запись в сети

Каждый аккаунт — это самостоятельный ключ, поэтому в PrivaMesh есть и лёгкий SOL-кошелёк для платежей и подарков в чате, плюс NFT-аватары и ники на блокчейне. Это вторично — главное это приватная переписка.

PrivaMesh работает в сети Solana mainnet. Сетевые действия стоят небольших комиссий в SOL. PrivaMesh не является криптобиржей — он только отправляет и принимает SOL между адресами, которыми ты владеешь.

Доверяй математике, а не компаниям.

---

## URLs (hosted on GitHub Pages)
- Privacy Policy URL: `https://makomest.github.io/PrivaMesh/privacy-policy.html`  ← required field
- Terms (EULA) URL: `https://makomest.github.io/PrivaMesh/terms.html`
- Support URL: `https://makomest.github.io/PrivaMesh/`  (or `https://github.com/Makomest/PrivaMesh`)
- Marketing URL: `https://makomest.github.io/PrivaMesh/`

---

## App Review notes (paste into "Notes for Reviewer")

```
PrivaMesh is a PRIVATE MESSENGER. It has no backend server — it communicates only
with the public Solana blockchain (a Solana RPC endpoint). Messages are end-to-end
encrypted and transported as encrypted memos in Solana transactions.

CLARIFICATION ON CRYPTO:
- PrivaMesh is NOT a cryptocurrency exchange and does NOT buy, sell, or convert
  crypto for fiat. Each account is simply a self-custodial key pair.
- Sending a message writes a small on-chain transaction, so it costs a tiny SOL
  network fee. This is a network fee, not an in-app purchase of crypto.
- The only in-app purchase (PrivaMesh+) is an auto-renewable subscription handled
  by StoreKit. NFT avatars/nicknames are cosmetic and do not unlock app features.

USER-GENERATED CONTENT MODERATION (Guideline 1.2):
- Terms of Use (zero-tolerance policy) and Privacy Policy are linked in the Profile tab.
- Users can BLOCK any contact (stops receiving their messages) and REPORT any user
  (Contact profile → Report; sends a pre-filled email to privamesh@proton.me).
- Because the app is end-to-end encrypted and serverless, moderation is client-side
  (block + report). We cannot read or remove message content.

HOW TO TEST:
1. Launch → accept Terms → create a wallet (you receive a seed phrase) OR import the
   test seed below.
2. To test messaging you need a second device/account. You can create two accounts
   (long-press the profile header → add account) and message between them, OR use the
   test wallet below which is funded with a small amount of SOL.

TEST WALLET (funded with SOL for review):
   Seed phrase: <PASTE 12-WORD TEST SEED HERE>
   (Import via Welcome → "Restore from seed phrase".)

If anything is unclear, contact privamesh@proton.me — thank you for reviewing.
```

> Before submitting: create a throwaway wallet, fund it with ~0.05 SOL, and paste its
> 12-word seed into the TEST WALLET section above. Never use your real seed.
