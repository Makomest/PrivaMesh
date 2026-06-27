//
//  PollingService.swift
//  privamesh
//
//  Polls getSignaturesForAddress every 30 seconds.
//  For each new memo transaction:
//    • Kind 0x02 → self-encrypted message (Saved Messages)
//    • Kind 0x00/0x01 → X3DH + Double Ratchet message from a contact
//

import Foundation
import SwiftData
import SolanaSwift

@Observable
final class PollingService {
    static let interval: TimeInterval = 8

    private(set) var isPolling  = false
    private(set) var lastPolledAt: Date?
    private(set) var lastError:    String?

    private var pollingTask: Task<Void, Never>?

    /// Don't fire notifications for the historical backlog on the first poll —
    /// only for events that arrive while the app is running.
    private var didInitialPoll = false

    // Per-account cursor so switching accounts doesn't cross signatures.
    private func lastSignature(for address: String) -> String? {
        UserDefaults.standard.string(forKey: "privamesh.polling.lastSig.\(address)")
    }
    private func setLastSignature(_ value: String?, for address: String) {
        UserDefaults.standard.set(value, forKey: "privamesh.polling.lastSig.\(address)")
    }

    // MARK: - Lifecycle

    func start(
        myAddress: String,
        identity: MessagingIdentityManager,
        rpc: SolanaRPCService,
        context: ModelContext
    ) {
        guard !isPolling else { return }
        isPolling  = true
        didInitialPoll = false   // don't notify this account's backlog on first poll
        pollingTask = Task {
            while !Task.isCancelled {
                await poll(myAddress: myAddress, identity: identity, rpc: rpc, context: context)
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling   = false
    }

    /// One poll cycle for a BGAppRefreshTask. `until: lastSignature` means every
    /// fetched signature is genuinely new, so we notify from the first cycle.
    @MainActor
    func pollOnceForBackground(
        myAddress: String,
        identity: MessagingIdentityManager,
        rpc: SolanaRPCService,
        context: ModelContext
    ) async {
        didInitialPoll = true
        await poll(myAddress: myAddress, identity: identity, rpc: rpc, context: context)
    }

    // MARK: - Single poll

    @MainActor
    func poll(
        myAddress: String,
        identity: MessagingIdentityManager,
        rpc: SolanaRPCService,
        context: ModelContext
    ) async {
        let config = RequestConfiguration(commitment: "confirmed", limit: 20, until: lastSignature(for: myAddress))
        do {
            let sigs  = try await rpc.client.getSignaturesForAddress(address: myAddress, configs: config)
            lastPolledAt = Date()
            lastError    = nil

            if let newest = sigs.first { setLastSignature(newest.signature, for: myAddress) }

            // Chronological order so DR ratchet advances correctly
            for info in sigs.reversed() {
                guard info.err == nil else { continue }
                let timestamp = info.blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                if let memo = info.memo, !memo.isEmpty {
                    await processIncomingMemo(
                        memo:            memo,
                        senderSignature: info.signature,
                        timestamp:       timestamp,
                        myAddress:       myAddress,
                        identity:        identity,
                        rpc:             rpc,
                        notify:          didInitialPoll,
                        context:         context
                    )
                } else if didInitialPoll {
                    // No memo → candidate incoming SOL payment.
                    await Self.maybeNotifyIncomingTransaction(
                        signature: info.signature, myAddress: myAddress,
                        endpointURL: rpc.currentEndpoint.address
                    )
                }
            }
            // Stealth chains: poll one-time addresses for each established contact.
            await pollStealthChains(myAddress: myAddress, identity: identity, rpc: rpc,
                                    notify: didInitialPoll, context: context)
            DisappearingMessages.purge(context: context)
            didInitialPoll = true
            // Reflect new unread messages on the app-icon badge (works in the
            // background poll too, so the count updates on the home screen).
            NotificationService.shared.refreshBadge(context: context, myAddress: myAddress)
        } catch {
            lastError = error.localizedDescription
            rpc.rotate()
        }
    }

    // MARK: - Dispatch a single memo

    @MainActor
    private func processIncomingMemo(
        memo:            String,
        senderSignature: String,
        timestamp:       Date,
        myAddress:       String,
        identity:        MessagingIdentityManager,
        rpc:             SolanaRPCService,
        notify:          Bool,
        context:         ModelContext
    ) async {
        // Deduplication — skip if already stored
        let dupDesc = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == senderSignature })
        if (try? context.fetchCount(dupDesc)) ?? 0 > 0 { return }

        // Strip optional Solana "[N] " prefix, then base64-decode to peek at kind byte
        let cleaned = memo.hasPrefix("[")
            ? String(memo.drop { $0 != " " }.dropFirst()).trimmingCharacters(in: .whitespaces)
            : memo

        guard let rawData = Data(base64Encoded: cleaned), !rawData.isEmpty else { return }

        if rawData[0] == 0x02 {
            // Self-encrypted envelope — handle separately
            await processSelfMemo(data: rawData, signature: senderSignature,
                                  timestamp: timestamp, myAddress: myAddress,
                                  identity: identity, context: context)
            return
        }

        // X3DH / DR envelope
        guard let envelope = try? MessageEnvelope.fromBase64(memo) else { return }
        let contactDesc = FetchDescriptor<Contact>()
        // Only this account's contacts (chats are scoped per account).
        let contacts = ((try? context.fetch(contactDesc)) ?? [])
            .filter { $0.ownerAddress == myAddress || $0.ownerAddress.isEmpty }

        switch envelope.kind {
        case .regular:
            // Needs an existing session — try each contact that has one.
            for contact in contacts where !contact.isSelf && !contact.isBlocked && contact.sessionData != nil {
                if let payload = tryDecrypt(envelope: envelope, contact: contact,
                                            identity: identity, context: context) {
                    store(payload, signature: senderSignature, timestamp: timestamp,
                          on: contact, notify: notify, context: context)
                    return
                }
            }

        case .sessionInit:
            // First message from someone. The envelope is self-contained, so we
            // can decrypt WITHOUT having the sender in contacts. Decrypt once,
            // then find-or-create the contact so the message (and a chat) appear.
            let myIdentity: CryptoIdentity
            do { myIdentity = try identity.getOrCreate() } catch { return }
            guard let result = Self.decryptSessionInit(envelope: envelope, myIdentity: myIdentity)
            else { return }

            // The sender's wallet address = the tx fee payer; needed so replies
            // land in their history and to attribute the chat correctly.
            let senderAddress = await Self.fetchSenderAddress(
                signature: senderSignature, endpointURL: rpc.currentEndpoint.address
            )

            let contact = findOrCreateContact(
                senderAddress: senderAddress,
                senderIdentityKey: envelope.senderIdentityPublic,
                ownerAddress: myAddress,
                in: contacts, context: context
            )
            contact.sessionData          = try? JSONEncoder().encode(result.ratchet)
            contact.stealthRoot          = result.stealthRoot
            contact.isInitiator          = false   // we received the sessionInit → responder
            contact.isSessionEstablished = true
            store(result.payload, signature: senderSignature, timestamp: timestamp,
                  on: contact, notify: notify, context: context)
        }
    }

    // MARK: - Stealth chains

    private static let stealthWindow = 5   // max new messages consumed per contact per cycle

    /// Poll the incoming one-time stealth addresses for every established contact.
    @MainActor
    private func pollStealthChains(myAddress: String, identity: MessagingIdentityManager,
                                   rpc: SolanaRPCService, notify: Bool, context: ModelContext) async {
        let desc = FetchDescriptor<Contact>()
        let contacts = ((try? context.fetch(desc)) ?? []).filter {
            !$0.isSelf && !$0.isBlocked && $0.ownerAddress == myAddress && $0.stealthRoot != nil
        }
        for contact in contacts {
            await pollContactStealth(contact, identity: identity, rpc: rpc, notify: notify, context: context)
        }
    }

    @MainActor
    private func pollContactStealth(_ contact: Contact, identity: MessagingIdentityManager,
                                    rpc: SolanaRPCService, notify: Bool, context: ModelContext) async {
        guard let root = contact.stealthRoot else { return }
        let label = contact.theirStealthLabel
        var index = contact.recvIndex
        var processed = 0
        while processed < Self.stealthWindow {
            guard let addr = StealthAddress.address(root: root, label: label, index: index) else { break }
            let config = RequestConfiguration(commitment: "confirmed", limit: 10)
            guard let sigs = try? await rpc.client.getSignaturesForAddress(address: addr, configs: config),
                  !sigs.isEmpty else { break }   // in-order: empty index → stop

            var consumed = false
            for info in sigs.reversed() {
                guard info.err == nil, let memo = info.memo, !memo.isEmpty else { continue }
                let ts = info.blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                if await processStealthMemo(memo: memo, signature: info.signature, timestamp: ts,
                                            contact: contact, identity: identity, notify: notify, context: context) {
                    consumed = true
                }
            }
            if consumed {
                index += 1
                contact.recvIndex = index
                try? context.save()
                processed += 1
            } else {
                break
            }
        }
    }

    /// Decrypt + store a regular message that arrived on a stealth address for
    /// `contact`. Returns true if consumed (incl. already-stored duplicates).
    @MainActor
    private func processStealthMemo(memo: String, signature: String, timestamp: Date,
                                    contact: Contact, identity: MessagingIdentityManager,
                                    notify: Bool, context: ModelContext) async -> Bool {
        let dup = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == signature })
        if (try? context.fetchCount(dup)) ?? 0 > 0 { return true }   // already consumed
        guard let envelope = try? MessageEnvelope.fromBase64(memo),
              contact.sessionData != nil,
              let payload = tryDecrypt(envelope: envelope, contact: contact, identity: identity, context: context)
        else { return false }
        store(payload, signature: signature, timestamp: timestamp, on: contact, notify: notify, context: context)
        return true
    }

    // MARK: - Store + contact resolution

    @MainActor
    private func store(_ payload: ChatPayload, signature: String, timestamp: Date,
                       on contact: Contact, notify: Bool, context: ModelContext) {
        // Decoy (cover traffic): already decrypted to keep the ratchet in sync;
        // drop it silently — no stored message, no notification.
        if payload.kind == .cover { return }

        let msg = ChatMessage(
            id:         signature,
            body:       payload.body,
            photoKey:   payload.photoKey,
            isOutgoing: false,
            sentAt:     timestamp,
            status:     "received"
        )
        msg.kind       = payload.kind.rawValue
        msg.solAmount  = payload.amountSOL
        msg.giftKind   = payload.giftKind
        msg.giftRef    = payload.giftRef
        msg.giftName   = payload.giftName
        msg.giftRarity = payload.giftRarity
        msg.giftClaimed = false
        msg.isRead     = false
        msg.contact    = contact
        context.insert(msg)

        // Learn the sender's real main wallet (for in-chat payments) — works even
        // when the on-chain fee payer was a gas wallet.
        if let w = payload.senderWallet, !w.isEmpty { contact.paymentAddress = w }

        // Adopt the sender's current nick + NFT avatar carried in the payload.
        if let nick = payload.senderNick, !nick.isEmpty {
            var snap = contact.profile ?? ProfileSnapshot()
            snap.nickname = nick
            if let seed = payload.senderAvatarSeed { snap.activeAvatarSeed = seed }
            contact.profileData = try? JSONEncoder().encode(snap)
            // Auto-created contacts (no bundle, generated name) adopt the real nick.
            if contact.prekeyBundleBase64.isEmpty { contact.displayName = nick }
        }

        try? context.save()

        if notify && !contact.isMuted && NotificationService.shared.activeChatId != contact.id {
            NotificationService.shared.notifyMessage(from: contact.primaryName)
        }
    }

    /// Best-effort: fetch a no-memo transaction and notify if it credited us SOL.
    /// Excludes our own sends (negative delta) and message txs (which have memos).
    private static func maybeNotifyIncomingTransaction(
        signature: String, myAddress: String, endpointURL: String
    ) async {
        guard let url = URL(string: endpointURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "getTransaction",
            "params": [signature, ["encoding": "json",
                                   "maxSupportedTransactionVersion": 0,
                                   "commitment": "confirmed"]]
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result  = json["result"] as? [String: Any],
              let meta    = result["meta"] as? [String: Any],
              let pre     = meta["preBalances"]  as? [Int],
              let post    = meta["postBalances"] as? [Int],
              let tx      = result["transaction"] as? [String: Any],
              let message = tx["message"] as? [String: Any],
              let keys    = message["accountKeys"] as? [String],
              let idx     = keys.firstIndex(of: myAddress),
              idx < pre.count, idx < post.count
        else { return }

        let deltaLamports = post[idx] - pre[idx]
        guard deltaLamports > 0 else { return }   // only incoming credits
        await MainActor.run {
            NotificationService.shared.notifyIncomingTransaction(
                amountSOL: Double(deltaLamports) / 1_000_000_000
            )
        }
    }

    /// Find the contact this sessionInit belongs to, or create a "message
    /// request" contact so an unknown sender's first message still appears.
    @MainActor
    private func findOrCreateContact(
        senderAddress: String?,
        senderIdentityKey: Data?,
        ownerAddress: String,
        in contacts: [Contact],
        context: ModelContext
    ) -> Contact {
        // 1. Match a contact already added via search/QR by Solana address.
        if let addr = senderAddress,
           let existing = contacts.first(where: { $0.id == addr }) {
            return existing
        }
        // 2. Match a contact by their messaging identity key (e.g. a prior
        //    auto-created one, or one added by bundle).
        if let ik = senderIdentityKey,
           let existing = contacts.first(where: {
               (try? PrekeyBundle.fromBase64($0.prekeyBundleBase64))?.dhIdentityKey == ik
           }) {
            return existing
        }
        // 3. New "message request" contact. Use the real address as id when we
        //    have it (so replies work); otherwise fall back to the identity key
        //    so the message is at least visible.
        let id = senderAddress
            ?? senderIdentityKey?.base64EncodedString()
            ?? UUID().uuidString
        let name = senderAddress.map { NicknameManager.generate(from: $0) } ?? "Новый контакт"
        let contact = Contact(id: id, displayName: name, prekeyBundleBase64: "")
        contact.ownerAddress = ownerAddress
        context.insert(contact)
        return contact
    }

    // MARK: - Self-message (kind 0x02)

    @MainActor
    private func processSelfMemo(
        data:      Data,
        signature: String,
        timestamp: Date,
        myAddress: String,
        identity:  MessagingIdentityManager,
        context:   ModelContext
    ) async {
        // Wire format: [0x02][nonce(12)][ciphertext][tag(16)] — minimum 29 bytes
        guard data.count > 29 else { return }

        do {
            let key       = try MessageSender.deriveSelfKey(identity: identity)
            let combined  = Data(data[1...])                          // strip kind byte
            let padded    = try CryptoBox.decrypt(combined: combined, key: key)
            let plaintext = try MessagePadding.unpad(padded)
            let payload   = ChatPayload.decode(from: plaintext)

            // The active account's Saved Messages (self id == own address).
            let selfDesc = FetchDescriptor<Contact>(predicate: #Predicate { $0.id == myAddress })
            guard let selfContact = try? context.fetch(selfDesc).first, selfContact.isSelf else { return }

            let msg = ChatMessage(
                id:         signature,
                body:       payload.body,
                photoKey:   payload.photoKey,
                isOutgoing: true,
                sentAt:     timestamp,
                status:     "sent"
            )
            msg.contact = selfContact
            context.insert(msg)
            try? context.save()
        } catch {
            // Wrong key or corrupt data — ignore silently
        }
    }

    // MARK: - X3DH + DR decrypt

    /// Decrypt a `.regular` message using an existing contact's ratchet session.
    private func tryDecrypt(
        envelope: MessageEnvelope,
        contact:  Contact,
        identity: MessagingIdentityManager,
        context:  ModelContext
    ) -> ChatPayload? {
        guard let sessionData = contact.sessionData,
              var ratchet = try? JSONDecoder().decode(DoubleRatchet.self, from: sessionData)
        else { return nil }
        do {
            let padded    = try ratchet.decrypt(message: envelope.message)
            let plaintext = try MessagePadding.unpad(padded)
            contact.sessionData          = try? JSONEncoder().encode(ratchet)
            contact.isSessionEstablished = true
            return ChatPayload.decode(from: plaintext)
        } catch {
            return nil
        }
    }

    /// Decrypt a `.sessionInit` envelope. Self-contained (uses the sender keys
    /// carried in the envelope + our identity), so it does NOT need the sender
    /// to be a known contact. Returns the message and the fresh ratchet to store.
    private static func decryptSessionInit(
        envelope: MessageEnvelope,
        myIdentity: CryptoIdentity
    ) -> (payload: ChatPayload, ratchet: DoubleRatchet, stealthRoot: Data)? {
        guard let senderIK = envelope.senderIdentityPublic,
              let senderEK = envelope.senderEphemeralPublic else { return nil }
        do {
            let sk = try X3DH.receiverSharedSecret(
                myIdentityKey:            try myIdentity.dhIdentityKey(),
                mySignedPrekey:           try myIdentity.signedPrekey(),
                senderIdentityKeyPublic:  senderIK,
                senderEphemeralKeyPublic: senderEK
            )
            var ratchet = DoubleRatchet.initReceiver(sharedSecret: sk,
                                                     localSPK: try myIdentity.signedPrekey())
            let padded    = try ratchet.decrypt(message: envelope.message)
            let plaintext = try MessagePadding.unpad(padded)
            return (ChatPayload.decode(from: plaintext), ratchet, StealthAddress.root(fromSharedSecret: sk))
        } catch {
            return nil
        }
    }

    /// Fetch the fee payer (= sender's wallet address) of a transaction so we
    /// can attribute and reply to an unknown sender. Best-effort.
    private static func fetchSenderAddress(signature: String, endpointURL: String) async -> String? {
        guard let url = URL(string: endpointURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "getTransaction",
            "params": [signature, ["encoding": "json",
                                   "maxSupportedTransactionVersion": 0,
                                   "commitment": "confirmed"]]
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result  = json["result"] as? [String: Any],
              let tx      = result["transaction"] as? [String: Any],
              let message = tx["message"] as? [String: Any],
              let keys    = message["accountKeys"] as? [String]
        else { return nil }
        // accountKeys[0] is always the fee payer (the sender).
        return keys.first
    }
}
