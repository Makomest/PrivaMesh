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
- EN: `End-to-end encrypted messages with no phone number and no email. Only the person you write to can read them. We pay every network fee for you.`
- RU: `Сквозное шифрование без номера телефона и email. Прочитать сообщение может только тот, кому ты пишешь. Все комиссии сети платим мы.`

## Keywords (max 100 bytes, comma-separated, no spaces — no brand names, no crypto terms)
- EN: `secure,privacy,encryption,e2e,messenger,chat,texting,messaging,keys,no ads,no phone number` (90 bytes)
- RU: `мессенджер,шифрование,безопасный,переписка,ключи` (92 bytes)

### Claims that must not go back in

1.2 (19) was rejected under 2.5.19 and 5.6 for metadata that described a
different app: the promotional text said "no servers" and "chats never leave
your device", the keywords said `serverless`, and screenshot 07 said "Nothing in
the middle — no server of ours" while every message goes through our relay.
None of these, in any language: `serverless`, "no servers", "no server of ours",
"nothing in the middle", "peer to peer", "military-grade", "verification badge"
for PrivaMesh+, "your chats never leave your device". Say what happens instead:
the relay passes each encrypted message to the blockchain and pays the fee, and
cannot read it.

### Two words that must not go back in

**`anonymous` and `secret`** — with their Russian equivalents `анонимный` and
`секрет`. The 1.1 version was rejected on 2 September 2026 under guideline 1.1,
Objectionable Content, naming the keywords field and nothing else. The
description, the screenshots and the name were not questioned.

Apple is not disputing the encryption. Anonymous-and-secret messaging is a
product category it has repeatedly pulled — apps where people send messages
nobody can attribute, which turn into harassment tools. The rejection's own
words are "any service that provides, or could be used to create, objectionable
content", and two keywords put the app in that category by themselves.

What replaced them says the same thing without the claim: the app needs no phone
number, keeps keys on the device and runs no account server. Those are
properties, not promises of unattributable speech.

The rejection also warns that resubmitting with similar marketing draws the same
or additional violations, so this is not a place to argue the point.

---

## Description (EN)

PrivaMesh is an end-to-end encrypted messenger. No phone number, no email: your account is a 12-word recovery phrase that stays on your phone.

HOW MESSAGES TRAVEL
Each message is encrypted on your phone and written to the public Solana blockchain, where only the person you write to can read it. Our relay passes it on and pays the network fee; it cannot read your messages and keeps no copy. You never need or handle cryptocurrency.

ON YOUR PHONE
Keys, contacts and decrypted chats stay on this device. Saved Messages come back when you restore your phrase on a new phone; chats with other people don't.

PROTECTION
• A new one-time address for every message
• Optional Face ID lock for your keys
• Disappearing messages
• Safety numbers to check a contact in person
• A duress code that erases the account from this phone

PRICING
Your first account gets 10 free messages a month. PrivaMesh+ subscriptions and message packs add more through In-App Purchase; PrivaMesh+ also adds a PrivaMesh+ badge and up to 3 accounts. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period; manage them in your Apple ID settings.

Anything you send stays on the blockchain permanently: unreadable without the keys, but impossible to delete.

## Description (RU)

PrivaMesh — мессенджер со сквозным шифрованием. Без номера телефона и email: твой аккаунт — фраза восстановления из 12 слов, которая хранится на телефоне.

КАК ИДУТ СООБЩЕНИЯ
Каждое сообщение шифруется на телефоне и записывается в публичный блокчейн Solana, где прочитать его может только тот, кому ты пишешь. Наш relay передаёт его и платит комиссию сети; прочитать сообщения он не может и копий не хранит. Криптовалюта тебе не нужна.

НА ТЕЛЕФОНЕ
Ключи, контакты и расшифрованные чаты хранятся только на этом устройстве. Избранное вернётся, если восстановить фразу на новом телефоне; чаты с другими людьми — нет.

ЗАЩИТА
• Новый одноразовый адрес для каждого сообщения
• Face ID на ключи — по желанию
• Исчезающие сообщения
• Номера безопасности, чтобы проверить собеседника при встрече
• Код на случай принуждения: стирает аккаунт с этого телефона

ЦЕНЫ
Первый аккаунт получает 10 бесплатных сообщений в месяц. Подписки PrivaMesh+ и пакеты сообщений добавляют больше через встроенные покупки; PrivaMesh+ также даёт значок PrivaMesh+ и до 3 аккаунтов. Подписка продлевается автоматически, если не отменить её минимум за 24 часа до конца периода; управление — в настройках Apple ID.

Всё отправленное остаётся в блокчейне навсегда: без ключей его не прочитать, но и удалить нельзя.

---

## URLs
- Privacy Policy URL: `https://privamesh.org/privacy-policy`  ← required
- Terms (EULA) URL: `https://privamesh.org/terms`
- Support URL: `https://privamesh.org/support`
- Marketing URL: `https://privamesh.org`

---

## App Review notes (paste into "Notes for Reviewer")

1.2 was rejected three times. Builds 15-18 carried dead NFT and SOL-transfer
code (2.3.1(a)); build 19 still linked SolanaSwift (2.3.1(a)); build 19 was then
rejected under 2.5.19 and 5.6 because the app recognised the review account and
staged chats for it, Settings had a switch for a feature that did not exist, and
the store text said there was no server between users. Build 21 fixes all
three; the notes below describe the app exactly as every account gets it.

```
PrivaMesh is an end-to-end encrypted messenger. The app behaves the same for
every account, including the demo account below, and no feature is switched on
remotely.

HOW MESSAGES ARE DELIVERED
- A message is encrypted on the device (X3DH + Double Ratchet) and sent to our
  relay, a Cloudflare Worker. The relay writes it to the public Solana
  blockchain as encrypted data and pays the network fee from our own account.
  It cannot read the message and keeps no copy.
- The app contains no blockchain, wallet or token library and builds no
  transactions. Users never hold, see, buy, send or receive cryptocurrency.
- Photos are encrypted on the device and stored on Arweave through Irys.
- The recovery phrase derives the user's messaging keys. It is an account key,
  not a wallet.

DEMO ACCOUNT
Welcome -> "Restore from recovery phrase" -> enter the phrase from the Sign-In
Information. After setting a passcode and accepting the Terms of Use, the Chats
screen shows two conversations, "PrivaMeshTeam" and "Alex42". Both are test
accounts we run; their messages were sent to the demo account over the network
before submission, the way any message arrives. Reply in either chat to send a
live message (each account has 10 free messages a month). "Saved Messages",
your chat with yourself, works without anyone else.

FEATURES AND WHERE THEY ARE
- Chats: a globe of contacts and a list view, search, unread counts.
- New contact ("+"): QR code, invite link, or search by nickname.
- In a chat: text and photos. Tap the contact's name at the top for
  disappearing messages, the safety number ("Verify contact"), mute, block
  and report.
- Profile: nickname, avatar, accounts (up to 3 with PrivaMesh+), messages left
  and purchases, "Search by nickname" (off until turned on), recovery phrase
  (behind the passcode).
- Profile -> Privacy: optional Face ID lock for the keys, show the PrivaMesh+
  badge to contacts.
- Profile -> Duress code: an optional second passcode. Entered at any passcode
  prompt, it erases the account from this phone and returns to the welcome
  screen. Its screen explains what it does and does not do.
- Profile -> Notifications: mute all, show or hide the sender's name.
- Profile -> RPC node: optionally read messages through another Solana RPC
  server instead of the default (Helius). Reading only; nothing is sent there.
- Profile -> Language: the app's language.
- Profile -> Legal: Terms of Use and Privacy Policy.
- In the background the app only checks for new messages (Background App
  Refresh). It sends only what the user asks for: messages, and the nickname
  record when the user turns on "Search by nickname" or reserves a nickname.

IN-APP PURCHASES
Profile -> "Messages left", or send until the free allowance is used:
PrivaMesh+ subscriptions and one-time message packs. They grant a message
allowance, the PrivaMesh+ badge and up to 3 accounts, nothing else.

USER-GENERATED CONTENT (Guideline 1.2)
- The Terms of Use (zero tolerance) are accepted before first use.
- Any contact can be blocked and any user or message reported.

REMOVED IN VERSION 1.2
- Build 18: leftover NFT, SOL-transfer and fee-wallet code.
- Build 19: the SolanaSwift library; the relay builds transactions instead.
- Build 21: sample conversations the app showed only to the review account; a
  disabled "Hide my IP through a mixnet" switch for a feature that did not
  exist; optional background decoy messages ("cover traffic"); publishing every
  account to the public nickname directory without asking (it is now off until
  the user turns it on); and wording in the app and on the store that said
  there was no server between users.

Encryption: end-to-end; export-exempt (ITSAppUsesNonExemptEncryption = NO).
```

## Resolution Center replies (1.2)

Third reply, for build 21 (Guidelines 2.5.19 and 5.6):

```
Hello,

Thank you. We found three things in build 19 that fit your description, and
build 21 removes them:

1. The app recognised the App Review demo account by its address and showed it
   sample conversations that no other account had. That code is gone. The demo
   account is now an ordinary new account; the two conversations in it are real
   messages that our test accounts sent to it over the network before
   submission.

2. Settings showed a disabled "Hide my IP through a mixnet" switch for a feature
   that does not exist. It is removed, together with an optional setting that
   sent invisible decoy messages in the background. The app also wrote every
   account into the public nickname directory on launch, whatever the "Search
   by nickname" switch said; it now publishes nothing until the user turns
   that switch on or reserves a nickname.

3. Our store text and screenshots said there was no server between users. In
   fact every message passes through our relay, which writes it to the public
   Solana blockchain and pays the fee, without being able to read it. The
   description, promotional text, keywords and screenshots now say so, as do
   the in-app explanations and the privacy policy. We also renamed the
   subscription's "verification badge" to "PrivaMesh+ badge", because it does
   not verify anyone.

The Notes for Review now list every feature and where to find it. The app
behaves the same for every account, and no feature is switched on remotely.

Best regards
```

Second reply, for build 19:

```
Hello,

Thank you for looking again. Build 18 still contained what you describe, and
build 19 removes it:

- The open-source SolanaSwift library is no longer in the app. We used it only
  to derive the account key from the recovery phrase and to assemble a message,
  but it brought token, swap and transfer code with it. Key derivation is now a
  few hundred lines of our own code, and the app no longer builds or signs any
  network transaction: it sends the encrypted message to our server, which
  writes it to the network and pays the fee.
- Build 18 also carried, by mistake, cached files from a developer tool that
  listed the names of code removed earlier. They are gone from the bundle.

There is no wallet, balance, transfer, token, NFT or trading code in the app.
Messages are end-to-end encrypted and delivered over the public Solana network;
we pay every network fee, and users pay only through In-App Purchase, for a
message allowance. The Notes for Review describe this in full.

Best regards
```

First reply, sent with build 18:

```
Hello,

Thank you for the review. You were right that the build contained code that was
not documented: an earlier, abandoned design for NFT avatars and nicknames, SOL
transfers and a fee wallet. None of it was reachable from any screen, but it
should not have shipped. Build 18 removes it completely.

We should also have stated plainly how messages are delivered, and we have now
done so in the Notes for Review and in the description: messages are encrypted
on the device and delivered over the public Solana network; the developer pays
every network fee from its own account; users never hold, see, send or receive
cryptocurrency, and there are no tokens, NFTs, balances or trading in the app.
Users pay only through In-App Purchase, for a message allowance.

We have submitted build 18 with these changes. Please let us know if anything
further needs clarifying.

Best regards
```

## What's New in 1.2 (EN / RU)

```
Clearer explanations of how messages are delivered, a PrivaMesh+ badge instead of a check mark, and many security and reliability fixes.
```

```
Понятнее объясняем, как доставляются сообщения; значок PrivaMesh+ вместо галочки; много исправлений безопасности и надёжности.
```
