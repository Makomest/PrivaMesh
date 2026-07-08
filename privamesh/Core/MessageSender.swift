//
//  MessageSender.swift
//  privamesh
//
//  Two send pipelines:
//
//  Regular contacts:
//    plaintext → pad → X3DH/DR.encrypt → MessageEnvelope[0x00/0x01] → base64 → Memo tx → Solana
//
//  Saved Messages (self):
//    plaintext → pad → AES-GCM(selfKey) → SelfEnvelope[0x02] → base64 → Memo tx → Solana (to own address)
//    Self-key = HKDF(dhIdentityKey, "privamesh-self-v1")  — deterministic, recoverable.
//

import Foundation
import SwiftData
import SolanaSwift

@Observable
final class MessageSender {
    enum State {
        case idle
        case sending
        case success(signature: String)
        case failure(message: String)
    }

    var state: State = .idle

    /// Sponsoring relay. When configured, message fees are paid by the app
    /// treasury and submitted via the relay instead of the user's wallet.
    /// Set by the app root; nil falls back to the direct (user-pays) path.
    var relay: RelayService?

    /// True when the last failure was the relay rejecting for quota — lets the UI
    /// present the paywall instead of a generic error (client mirror can drift).
    private(set) var lastFailureIsQuota = false

    // Sender's public identity, stamped onto outgoing payloads so recipients
    // see the real nick + NFT avatar without exchanging QR.
    private var senderNick: String?
    private var senderAvatarSeed: String?
    private var senderWallet: String?
    private var senderIsPremium = false

    func setSenderProfile(nick: String?, avatarSeed: String?, wallet: String? = nil,
                          isPremium: Bool = false) {
        senderNick = nick
        senderAvatarSeed = avatarSeed
        senderWallet = wallet
        senderIsPremium = isPremium
    }

    private func stamp(_ payload: ChatPayload) -> ChatPayload {
        var p = payload
        p.senderNick = senderNick
        p.senderAvatarSeed = senderAvatarSeed
        p.senderWallet = senderWallet
        p.senderIsPremium = senderIsPremium ? true : nil
        return p
    }

    /// User-facing send failures with precise, actionable messages.
    /// Replaces opaque low-level errors (e.g. CryptoError.invalidData → "Malformed data")
    /// so the failing stage is unambiguous.
    enum SendError: LocalizedError {
        case corruptContactBundle(name: String)
        case invalidRecipientAddress(name: String)

        var errorDescription: String? {
            switch self {
            case .corruptContactBundle(let name):
                return String(localized: "Контакт «\(name)» повреждён (нет валидного prekey-бандла). Удали и добавь его заново.")
            case .invalidRecipientAddress(let name):
                return String(localized: "У контакта «\(name)» некорректный Solana-адрес получателя. Добавь его заново через поиск, а не QR.")
            }
        }
    }

    // MARK: - Send text

    @MainActor
    func send(
        text: String,
        to contact: Contact,
        senderKeyPair: KeyPair,
        identity: MessagingIdentityManager,
        rpc: SolanaRPCService,
        context: ModelContext
    ) async {
        state = .sending
        lastFailureIsQuota = false
        let startedAt = Date()

        // Show message immediately; update id/status once blockchain confirms
        let msg = ChatMessage(id: UUID().uuidString, body: text,
                              isOutgoing: true, sentAt: Date(), status: "sending")
        msg.contact = contact
        context.insert(msg)
        try? context.save()

        do {
            // Stage 1: encrypt + build the memo payload (local crypto only).
            let memoBase64: String
            var built: BuiltEnvelope?
            do {
                let plaintext = try stamp(.text(text)).encode()
                let padded    = MessagePadding.pad(plaintext)
                if contact.isSelf {
                    memoBase64 = try Self.buildSelfMemo(padded: padded, identity: identity)
                } else {
                    let envelope = try buildEnvelope(padded: padded, contact: contact, identity: identity)
                    built = envelope
                    memoBase64 = envelope.base64
                }
            } catch {
                throw Self.tag(error, stage: "ШИФРОВАНИЕ")
            }

            // Stage 2: submit to Solana (network / RPC).
            let signature: String
            do {
                signature = try await submitMemo(
                    memoBase64: memoBase64,
                    recipientAddress: built?.sendAddress ?? contact.id,
                    senderKeyPair: senderKeyPair,
                    rpc: rpc
                )
            } catch {
                if case RelayService.RelayError.quotaExceeded = error { lastFailureIsQuota = true }
                throw Self.tag(error, stage: "СЕТЬ/RPC")
            }

            // Commit the advanced ratchet ONLY now that the send succeeded.
            built?.commit(on: contact)
            msg.id     = signature
            msg.status = "sent"
            msg.feeLamports     = Int(rpc.estimatedFeeLamports)
            msg.deliverySeconds = Date().timeIntervalSince(startedAt)
            try? context.save()
            state = .success(signature: signature)
        } catch {
            msg.status = "failed"
            try? context.save()
            state = .failure(message: error.localizedDescription)
        }
    }

    /// Wrap an error with the failing stage + concrete type so the surfaced
    /// message is never the ambiguous bare "Malformed data".
    private static func tag(_ error: Error, stage: String) -> Error {
        if error is SendError { return error }   // already actionable
        let type = String(describing: Swift.type(of: error))
        let msg  = "[\(stage)] \(error.localizedDescription) (\(type))"
        #if DEBUG
        print("⛏️ MessageSender send failed — \(msg)")
        #endif
        return NSError(domain: "MessageSender",
                       code: 0,
                       userInfo: [NSLocalizedDescriptionKey: msg])
    }

    func reset() { state = .idle }

    // MARK: - Send SOL note / NFT gift

    /// Sends the encrypted "I sent you N SOL" message. The actual transfer is
    /// done by the caller (it has the wallet); this records it in the chat.
    @MainActor
    func sendSOLNote(amount: Double, signature: String, to contact: Contact,
                     senderKeyPair: KeyPair, identity: MessagingIdentityManager,
                     rpc: SolanaRPCService, context: ModelContext) async {
        let msg = ChatMessage(id: UUID().uuidString, body: "", isOutgoing: true,
                              sentAt: Date(), status: "sending")
        msg.kind = "sol"; msg.solAmount = amount; msg.contact = contact
        await deliver(.sol(amount: amount, signature: signature), msg: msg, to: contact,
                      senderKeyPair: senderKeyPair, identity: identity, rpc: rpc, context: context)
    }

    /// Gifts an owned NFT (avatar/nickname). Caller removes it from their own
    /// collection; the recipient claims it on their side.
    @MainActor
    func sendGift(itemKind: String, ref: String, name: String, rarity: String?,
                  to contact: Contact, senderKeyPair: KeyPair, identity: MessagingIdentityManager,
                  rpc: SolanaRPCService, context: ModelContext) async {
        let msg = ChatMessage(id: UUID().uuidString, body: "", isOutgoing: true,
                              sentAt: Date(), status: "sending")
        msg.kind = "gift"; msg.giftKind = itemKind; msg.giftRef = ref
        msg.giftName = name; msg.giftRarity = rarity; msg.giftClaimed = true
        msg.contact = contact
        await deliver(.gift(kind: itemKind, ref: ref, name: name, rarity: rarity), msg: msg,
                      to: contact, senderKeyPair: senderKeyPair, identity: identity, rpc: rpc, context: context)
    }

    /// Shared encrypt → submit pipeline for a pre-built outgoing message.
    @MainActor
    private func deliver(_ payload: ChatPayload, msg: ChatMessage, to contact: Contact,
                         senderKeyPair: KeyPair, identity: MessagingIdentityManager,
                         rpc: SolanaRPCService, context: ModelContext) async {
        state = .sending
        let startedAt = Date()
        context.insert(msg)
        try? context.save()
        do {
            let memoBase64: String
            var built: BuiltEnvelope?
            do {
                let padded = MessagePadding.pad(try stamp(payload).encode())
                if contact.isSelf {
                    memoBase64 = try Self.buildSelfMemo(padded: padded, identity: identity)
                } else {
                    let envelope = try buildEnvelope(padded: padded, contact: contact, identity: identity)
                    built = envelope
                    memoBase64 = envelope.base64
                }
            } catch { throw Self.tag(error, stage: "ШИФРОВАНИЕ") }

            let signature: String
            do {
                signature = try await submitMemo(memoBase64: memoBase64, recipientAddress: built?.sendAddress ?? contact.id,
                                                 senderKeyPair: senderKeyPair, rpc: rpc)
            } catch { throw Self.tag(error, stage: "СЕТЬ/RPC") }

            built?.commit(on: contact)
            msg.id = signature; msg.status = "sent"
            msg.feeLamports = Int(rpc.estimatedFeeLamports)
            msg.deliverySeconds = Date().timeIntervalSince(startedAt)
            try? context.save()
            state = .success(signature: signature)
        } catch {
            msg.status = "failed"
            try? context.save()
            state = .failure(message: error.localizedDescription)
        }
    }

    // MARK: - Cover traffic

    /// Sends a decoy message on the contact's stealth chain. No UI, no
    /// notification — it advances the ratchet/stealth index exactly like a real
    /// message so observers can't tell decoys from real ones. Only fires for an
    /// already-established session (never a sessionInit). Failures are silent.
    @MainActor
    func sendCover(to contact: Contact, senderKeyPair: KeyPair,
                   identity: MessagingIdentityManager,
                   rpc: SolanaRPCService, context: ModelContext) async {
        guard !contact.isSelf, contact.sessionData != nil, contact.stealthRoot != nil else { return }
        do {
            let padded = MessagePadding.pad(try ChatPayload.cover().encode())
            let built  = try buildEnvelope(padded: padded, contact: contact, identity: identity)
            let sig = try await submitMemo(memoBase64: built.base64,
                                           recipientAddress: built.sendAddress,
                                           senderKeyPair: senderKeyPair, rpc: rpc)
            built.commit(on: contact)
            try? context.save()
            #if DEBUG
            print("⛏️ cover sent to \(contact.displayName) sig=\(sig.prefix(8))")
            #endif
        } catch {
            #if DEBUG
            print("⛏️ cover send failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Send photo

#if os(iOS)
    @MainActor
    func sendPhoto(
        image: UIImage,
        to contact: Contact,
        senderKeyPair: KeyPair,
        identity: MessagingIdentityManager,
        rpc: SolanaRPCService,
        context: ModelContext
    ) async {
        state = .sending
        let startedAt = Date()

        // Show placeholder immediately; populate txId/key once upload+blockchain confirm
        let msg = ChatMessage(id: UUID().uuidString, body: "",
                              isOutgoing: true, sentAt: Date(), status: "sending")
        msg.contact = contact
        context.insert(msg)
        try? context.save()

        do {
            let compressed           = try PhotoEncryptor.compressForSend(image)
            let (encrypted, keyB64)  = try PhotoEncryptor.encrypt(compressed)
            let txId                 = try await IrysUploader.upload(encrypted, keypair: senderKeyPair)

            let plaintext  = try stamp(.photo(txId: txId, key: keyB64)).encode()
            let padded     = MessagePadding.pad(plaintext)
            let memoBase64: String

            var built: BuiltEnvelope?
            if contact.isSelf {
                memoBase64 = try Self.buildSelfMemo(padded: padded, identity: identity)
            } else {
                let envelope = try buildEnvelope(padded: padded, contact: contact, identity: identity)
                built = envelope
                memoBase64 = envelope.base64
            }

            let signature = try await submitMemo(
                memoBase64: memoBase64,
                recipientAddress: built?.sendAddress ?? contact.id,
                senderKeyPair: senderKeyPair,
                rpc: rpc
            )

            built?.commit(on: contact)
            msg.id       = signature
            msg.body     = txId
            msg.photoKey = keyB64
            msg.status   = "sent"
            msg.feeLamports     = Int(rpc.estimatedFeeLamports)
            msg.deliverySeconds = Date().timeIntervalSince(startedAt)
            try? context.save()
            state = .success(signature: signature)
        } catch {
            msg.status = "failed"
            try? context.save()
            state = .failure(message: error.localizedDescription)
        }
    }
#endif

    // MARK: - Self-envelope helpers (internal so PollingService can reuse deriveSelfKey)

    /// Build a kind-0x02 self-envelope: [0x02][nonce(12)][ciphertext][tag(16)]
    static func buildSelfMemo(padded: Data, identity: MessagingIdentityManager) throws -> String {
        let key      = try deriveSelfKey(identity: identity)
        let combined = try CryptoBox.encrypt(plaintext: padded, key: key)
        var envelope = Data([0x02])
        envelope.append(combined)
        return envelope.base64EncodedString()
    }

    /// Derive a deterministic self-encryption key from the messaging identity DH key.
    static func deriveSelfKey(identity: MessagingIdentityManager) throws -> Data {
        let id    = try identity.getOrCreate()
        let dhKey = try id.dhIdentityKey()
        return CryptoBox.hkdf(
            inputKeyMaterial: dhKey.rawRepresentation,
            salt: Data(count: 32),
            info: Data("privamesh-self-v1".utf8),
            outputByteCount: 32
        )
    }

    // MARK: - X3DH + DR envelope builder

    /// Result of building an outgoing envelope. The new ratchet state is NOT
    /// written to the contact here — only after the tx actually succeeds (via
    /// `commit(on:)`). This prevents a failed send from advancing/establishing
    /// the session, which would make the next message a `.regular` one that the
    /// recipient (who never got the sessionInit) can't decrypt.
    private struct BuiltEnvelope {
        let base64: String
        let newSessionData: Data
        let newEphemeral: Data?    // set only for the first (sessionInit) message
        let newStealthRoot: Data?  // set only for the first message (we're the initiator)
        let sendAddress: String    // where to actually send (real for bootstrap, else stealth)
        let usedStealthIndex: Int? // the stealth send index used (advance on success)

        func commit(on contact: Contact) {
            contact.sessionData = newSessionData
            if let ek = newEphemeral { contact.myEphemeralKeyData = ek }
            if let root = newStealthRoot {
                contact.stealthRoot = root
                contact.isInitiator = true
            }
            if let idx = usedStealthIndex { contact.sendIndex = idx + 1 }
            contact.isSessionEstablished = true
        }
    }

    private func buildEnvelope(
        padded: Data,
        contact: Contact,
        identity: MessagingIdentityManager
    ) throws -> BuiltEnvelope {
        let myIdentity = try identity.getOrCreate()

        var ratchet: DoubleRatchet
        let isFirst: Bool
        var ephemeral: Data?
        var stealthRoot: Data?

        if let sessionData = contact.sessionData,
           let existing = try? JSONDecoder().decode(DoubleRatchet.self, from: sessionData) {
            ratchet  = existing
            isFirst  = false
        } else {
            guard !contact.prekeyBundleBase64.isEmpty,
                  let bundle = try? PrekeyBundle.fromBase64(contact.prekeyBundleBase64) else {
                throw SendError.corruptContactBundle(name: contact.displayName)
            }
            let ek  = CryptoKit.Curve25519.KeyAgreement.PrivateKey()
            let sk  = try X3DH.senderSharedSecret(
                myIdentityKey:  try myIdentity.dhIdentityKey(),
                myEphemeralKey: ek,
                remoteBundle:   bundle
            )
            ratchet     = try DoubleRatchet.initSender(sharedSecret: sk, remoteSPKPublic: bundle.signedPrekeyPublic)
            ephemeral   = ek.rawRepresentation
            stealthRoot = StealthAddress.root(fromSharedSecret: sk)
            isFirst     = true
        }

        let message     = try ratchet.encrypt(plaintext: padded)
        let newSession  = try JSONEncoder().encode(ratchet)

        // Destination: bootstrap (first message) → real address so the recipient
        // catches it on their own address; afterwards → one-time stealth address
        // on my chain (recipient polls the same chain).
        let sendAddress: String
        let usedStealthIndex: Int?
        if !isFirst, let root = contact.stealthRoot,
           let addr = StealthAddress.address(root: root, label: contact.myStealthLabel, index: contact.sendIndex) {
            sendAddress = addr
            usedStealthIndex = contact.sendIndex
        } else {
            sendAddress = contact.id
            usedStealthIndex = nil
        }

        let envelope: MessageEnvelope
        if isFirst {
            let dhIK = try myIdentity.dhIdentityKey()
            let ek   = try CryptoKit.Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ephemeral!)
            envelope = MessageEnvelope(
                kind: .sessionInit,
                senderIdentityPublic:  dhIK.publicKey.rawRepresentation,
                senderEphemeralPublic: ek.publicKey.rawRepresentation,
                message: message
            )
        } else {
            envelope = MessageEnvelope(kind: .regular, senderIdentityPublic: nil,
                                       senderEphemeralPublic: nil, message: message)
        }
        return BuiltEnvelope(base64: envelope.base64, newSessionData: newSession,
                             newEphemeral: ephemeral, newStealthRoot: stealthRoot,
                             sendAddress: sendAddress, usedStealthIndex: usedStealthIndex)
    }

    // MARK: - Solana submission with RPC rotation

    private func submitMemo(
        memoBase64: String,
        recipientAddress: String,
        senderKeyPair: KeyPair,
        rpc: SolanaRPCService
    ) async throws -> String {
        // Fail fast if the recipient isn't a valid 32-byte Solana address.
        // CRITICAL: PublicKey(string:) only checks the string is >= 32 *chars*;
        // it does NOT verify Base58.decode produced 32 *bytes*. A base64 id
        // (e.g. a QR contact storing base64(DH key)) contains '+', '/', '='
        // which aren't base58, so decode yields EMPTY bytes and the key
        // silently serializes to 0 bytes — corrupting the transaction by 32
        // bytes. Validate the byte length explicitly.
        guard let recipientKey = try? PublicKey(string: recipientAddress),
              recipientKey.bytes.count == PublicKey.numberOfBytes else {
            throw SendError.invalidRecipientAddress(name: recipientAddress)
        }

        // Sponsored path: the app treasury pays the fee via the relay, so the
        // user needs no SOL. Used whenever the relay is configured.
        if let relay, relay.isConfigured {
            return try await relay.sendMessage(
                to: recipientAddress,
                memoBase64: memoBase64,
                endpointURL: rpc.currentEndpoint.address,
                computeUnitLimit: 600_000)
        }

        // Try every endpoint, collecting each failure. Throwing only the LAST
        // error used to hide the real cause behind whichever node happened to be
        // last in the rotation (e.g. a dead Ankr 403).
        var failures: [String] = []
        for _ in 0..<rpc.endpoints.count {
            let endpoint = rpc.currentEndpoint.address
            do {
                return try await MemoTransactionBuilder.send(
                    from: senderKeyPair,
                    to: recipientAddress,
                    memoBase64: memoBase64,
                    endpointURL: endpoint,
                    apiClient: rpc.client,
                    // Raise the Memo program's compute budget. A 512-byte padding
                    // bucket (SOL-note/gift payloads carry a tx signature + sender
                    // stamps → push past 256) yields a ~770-byte memo that fails
                    // with "Program failed to complete" on the default budget.
                    // 600k CU covers it; at 1000 µLamports/CU that's <0.0000006 SOL.
                    computeUnitLimit: 600_000
                )
            } catch {
                let host = URL(string: endpoint)?.host ?? endpoint
                failures.append("• \(host): \(error.localizedDescription)")
                rpc.rotate()
            }
        }
        throw NSError(domain: "MessageSender", code: 0, userInfo: [
            NSLocalizedDescriptionKey:
                "Все RPC-эндпоинты отклонили транзакцию:\n" + failures.joined(separator: "\n")
        ])
    }
}

import CryptoKit
#if os(iOS)
import UIKit
#endif
