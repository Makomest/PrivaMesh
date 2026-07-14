# PrivaMesh — App Store Listing & Review Notes

Copy-paste fields for App Store Connect. Position the app as a **private messenger** — no cryptocurrency, no wallet.

---

## App name
`PrivaMesh: Private Messenger`

## Subtitle (max 30 chars)
- EN: `Encrypted private messenger`
- RU: `Приватный мессенджер`

## Category
- Primary: **Social Networking**
- Secondary: Utilities

## Age rating
**17+** (unrestricted user-generated content / messaging)

## Promotional text (max 170 chars)
- EN: `Private messaging with no servers, no phone number, no email. End-to-end encrypted. Your keys and chats never leave your device.`
- RU: `Приватные сообщения без серверов, без номера телефона, без email. Сквозное шифрование. Ключи и переписка не покидают устройство.`

## Keywords (max 100 chars, comma-separated, no spaces — no brand names, no crypto terms)
- EN: `private,secure,chat,anonymous,messaging,no phone,privacy,secret,e2e,safe,vault,cipher,offgrid,nolog`
- RU: `мессенджер,приватный,шифрование,анонимный,безопасный,чат,без телефона,приватность,секрет,защита`

---

## Description (EN)

PrivaMesh is a private, end-to-end encrypted messenger for people who don't want their conversations logged, mined, or sold. No phone number. No email. No profile. Just a key that belongs to you.

PRIVATE BY DESIGN
Everything personal stays on your device — your identity, your contacts, your chat history. There's no account database and nothing about you to leak. Your keys never leave your phone.

NO PHONE, NO EMAIL
Sign up with nothing at all. No phone number, no email, no personal data. Your identity is a key you own, stored in the iOS Keychain and locked with Face ID / Touch ID.

REAL END-TO-END ENCRYPTION
PrivaMesh uses a proven cryptographic core: X3DH for the initial handshake and the Double Ratchet for ongoing messages — the same family of protocols trusted by the world's leading secure messengers. Forward secrecy means even a compromised key can't unlock your past conversations.

METADATA-RESISTANT
No central profile of your social graph. Who you talk to, when, and how often isn't collected, logged, or sold.

YOUR IDENTITY, YOUR CONTROL
Pick a unique nickname so friends can find you — no contact-list upload, no data harvesting. You hold your own recovery phrase: back it up once and restore your account on any device.

PRIVAMESH+ (optional)
PrivaMesh+ unlocks a higher monthly message allowance and a verification badge. Auto-renewable subscription; payment is charged to your Apple ID and renews unless canceled at least 24 hours before the period ends. Manage or cancel anytime in Apple ID settings.

Private messaging the way it should be: your words, your keys, your device. Trust math, not companies.

## Description (RU)

PrivaMesh — приватный мессенджер со сквозным шифрованием для тех, кто не хочет, чтобы их переписку логировали, анализировали или продавали. Без номера телефона. Без email. Без профиля. Только ключ, который принадлежит тебе.

ПРИВАТНОСТЬ ПО УМОЛЧАНИЮ
Всё личное остаётся на устройстве — личность, контакты, история переписки. Нет базы аккаунтов и нечего утекать. Ключи не покидают телефон.

БЕЗ ТЕЛЕФОНА И EMAIL
Регистрация вообще без данных. Твоя личность — ключ, который хранится в iOS Keychain и защищён Face ID / Touch ID.

НАСТОЯЩЕЕ СКВОЗНОЕ ШИФРОВАНИЕ
X3DH для рукопожатия и Double Ratchet для сообщений — семейство протоколов, которому доверяют ведущие защищённые мессенджеры. Forward secrecy: даже скомпрометированный ключ не раскроет прошлую переписку.

УСТОЙЧИВОСТЬ К МЕТАДАННЫМ
Никакого центрального профиля твоих связей. Кто, когда и как часто — не собирается и не продаётся.

ТВОЯ ЛИЧНОСТЬ — ТВОЙ КОНТРОЛЬ
Выбери уникальный ник, чтобы тебя находили — без загрузки контактов. Фраза восстановления только у тебя: сохрани один раз и восстанови аккаунт на любом устройстве.

PRIVAMESH+ (опционально)
PrivaMesh+ открывает больший месячный лимит сообщений и галочку верификации. Автопродление; оплата с Apple ID, продлевается, если не отменить за 24 часа до конца периода. Управление в настройках Apple ID.

Доверяй математике, а не компаниям.

---

## URLs
- Privacy Policy URL: `https://privamesh.org/privacy-policy.html`  ← required
- Terms (EULA) URL: `https://privamesh.org/terms.html`
- Support URL: `https://privamesh.org`
- Marketing URL: `https://privamesh.org`

---

## App Review notes (paste into "Notes for Reviewer")

```
PrivaMesh is a private, end-to-end encrypted messenger. It is NOT a cryptocurrency
wallet — there is no wallet, no balance, no buy/sell/exchange, and no trading
anywhere in the app. Users create an on-device identity key and send encrypted
messages; that is the entire experience.

The app has no traditional login — an identity key is generated on device. For
review we provide a DEMO account: restoring its recovery phrase pre-populates the
app with sample contacts and two-way conversations so all features are verifiable.

DEMO ACCOUNT — restore this recovery phrase:
Welcome screen -> "Restore from recovery phrase" -> enter:

drum need person expire large wrist struggle labor label ill improve cloud

After restoring and setting a passcode, the Chats screen shows pre-populated
conversations (Alice, Bob, Decart) demonstrating the full messaging UI
(end-to-end encryption, message info, block/report, etc.).

SEND A LIVE MESSAGE (no purchase needed):
Each account includes a small free monthly message allowance. Open the "Decart"
chat and send a message, or Chats -> "+" -> search "Decart" -> add -> message it.
All delivery/infrastructure costs are covered by us, the developer. Users never
buy, hold, send, or spend any cryptocurrency.

IN-APP PURCHASES:
To add messages, open Profile -> the "Messages left" tile (or send until the free
allowance is used) to reach the purchase screen: subscriptions (PrivaMesh+
Starter/Pro) and consumable message packs. Test in the StoreKit sandbox. IAP
grants only a message allowance and membership perks — no cryptocurrency, token,
or digital asset is ever sold.

USER-GENERATED CONTENT MODERATION (Guideline 1.2):
- Terms of Use (zero-tolerance policy) and Privacy Policy are linked in the app.
- Users can BLOCK any contact and REPORT any user or message.
- The app is end-to-end encrypted, so moderation is client-side (block + report).

Encryption: end-to-end; export-exempt (ITSAppUsesNonExemptEncryption = NO).
iPhone-only.

If anything is unclear, contact privamesh@proton.me — thank you for reviewing.
```
