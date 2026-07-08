//
//  MemoTransactionBuilder.swift
//  privamesh
//
//  Builds a Solana transaction:
//    1. SystemProgram.transfer(from, to, 1 lamport)  — puts tx in recipient's history
//    2. Memo instruction (Memo v2)                   — carries base64 encrypted message
//
//  All RPC calls (getLatestBlockhash, sendTransaction) are made directly via URLSession
//  with JSONSerialization to avoid SolanaSwift's flawed JSON decoders that throw
//  raw DecodingErrors when endpoints return error responses or unexpected formats.
//

import Foundation
import SolanaSwift

enum MemoTransactionBuilder {
    static let memoProgramId = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
    /// 0 lamports: the transfer's only job is to put the recipient in the tx
    /// account keys so getSignaturesForAddress finds it. Sending ANY positive
    /// amount to a fresh (stealth) address creates a sub-rent-exempt account and
    /// the runtime rejects the tx ("insufficient funds for rent"). A 0-lamport
    /// transfer references the address without creating/funding it.
    static let lamportsPerMessage: UInt64 = 0

    static let computeBudgetProgramId = "ComputeBudget111111111111111111111111111111"
    static let computeUnitPriceMicroLamports: UInt64 = 1_000

    /// SetComputeUnitPrice (priority fee) + optionally SetComputeUnitLimit.
    /// Small memos run fine on the default budget, but a LARGE memo (e.g. the
    /// discovery bundle) makes the Memo program exceed its default per-tx compute
    /// and fail with "Program failed to complete" — pass `computeUnitLimit` to
    /// raise it. At 1000 µLamports/CU even a 1M limit costs <0.000001 SOL.
    private static func priorityInstructions(computeUnitLimit: UInt32? = nil) throws -> [TransactionInstruction] {
        let program = try PublicKey(string: computeBudgetProgramId)
        var out: [TransactionInstruction] = []
        if let limit = computeUnitLimit {
            var limitData = Data([2])                              // SetComputeUnitLimit
            withUnsafeBytes(of: limit.littleEndian) { limitData.append(contentsOf: $0) }
            out.append(TransactionInstruction(keys: [], programId: program, data: Array(limitData)))
        }
        var priceData = Data([3])                                  // SetComputeUnitPrice
        withUnsafeBytes(of: computeUnitPriceMicroLamports.littleEndian) { priceData.append(contentsOf: $0) }
        out.append(TransactionInstruction(keys: [], programId: program, data: Array(priceData)))
        return out
    }

    // MARK: - Main entry point

    static func send(
        from keypair: KeyPair,
        to recipientAddress: String,
        memoBase64: String,
        endpointURL: String,
        apiClient: SolanaAPIClient,
        computeUnitLimit: UInt32? = nil
    ) async throws -> String {
        let memoProgram = try PublicKey(string: memoProgramId)
        let recipient   = try PublicKey(string: recipientAddress)
        // PublicKey(string:) does not validate that the address decodes to 32
        // bytes — an invalid-base58 string yields an empty key that silently
        // corrupts the serialized tx. Guard against it here too.
        guard recipient.bytes.count == PublicKey.numberOfBytes else {
            throw rpcFail(method: "build", "адрес получателя не является валидным Solana-адресом (\(recipientAddress))")
        }

        let transferInstruction = SystemProgram.transferInstruction(
            from: keypair.publicKey,
            to: recipient,
            lamports: lamportsPerMessage
        )
        let memoInstruction = TransactionInstruction(
            keys: [AccountMeta(publicKey: keypair.publicKey, isSigner: true, isWritable: false)],
            programId: memoProgram,
            data: Array(memoBase64.utf8)
        )

        let blockhash = try await fetchLatestBlockhash(endpointURL: endpointURL)

        var transaction = Transaction(
            instructions: try priorityInstructions(computeUnitLimit: computeUnitLimit) + [transferInstruction, memoInstruction],
            recentBlockhash: blockhash,
            feePayer: keypair.publicKey
        )
        try transaction.sign(signers: [keypair])

        let serialized = try transaction.serialize().bytes.toBase64()
        return try await sendRawTransaction(serialized: serialized, endpointURL: endpointURL)
    }

    /// Build a message tx whose network fee is paid by the app treasury (the
    /// relay co-signs as fee payer). The sender partial-signs locally — proving
    /// memo authorship and sourcing the 0-lamport marker — while the treasury
    /// signature (fee payer) is added by the relay before submission. Returns the
    /// partially-signed transaction as base64. Users therefore never hold or
    /// spend SOL; access is metered via Apple IAP (see MessageQuotaService).
    static func buildSponsoredMessageBase64(
        to recipientAddress: String,
        memoBase64: String,
        treasury: PublicKey,
        endpointURL: String,
        computeUnitLimit: UInt32? = nil
    ) async throws -> String {
        let memoProgram = try PublicKey(string: memoProgramId)
        let recipient   = try PublicKey(string: recipientAddress)
        guard recipient.bytes.count == PublicKey.numberOfBytes else {
            throw rpcFail(method: "build", "адрес получателя не является валидным Solana-адресом (\(recipientAddress))")
        }
        // Per-message EPHEMERAL signer — a fresh throwaway keypair, never the real
        // wallet. The 0-lamport transfer needs no funds, and authorship is proven
        // by the encrypted Double Ratchet payload, not the on-chain signature. So
        // the sender's real address NEVER appears on-chain (only this random key +
        // the treasury fee payer + the recipient's one-time address).
        let ephemeral = try await KeyPair(network: .mainnetBeta)

        let transferInstruction = SystemProgram.transferInstruction(
            from: ephemeral.publicKey, to: recipient, lamports: lamportsPerMessage)
        let memoInstruction = TransactionInstruction(
            keys: [AccountMeta(publicKey: ephemeral.publicKey, isSigner: true, isWritable: false)],
            programId: memoProgram, data: Array(memoBase64.utf8))

        let blockhash = try await fetchLatestBlockhash(endpointURL: endpointURL)
        var transaction = Transaction(
            instructions: try priorityInstructions(computeUnitLimit: computeUnitLimit) + [transferInstruction, memoInstruction],
            recentBlockhash: blockhash,
            feePayer: treasury)                            // app treasury pays the fee
        try transaction.partialSign(signers: [ephemeral])  // ephemeral fills its slots
        // requiredAllSignatures:false → leaves the treasury (fee-payer) slot empty
        // for the relay to fill.
        return try transaction.serialize(requiredAllSignatures: false).bytes.toBase64()
    }

    /// Build an arbitrary instruction list as a treasury-sponsored, partially
    /// signed transaction (fee payer = treasury; the given signers sign locally,
    /// the relay adds the treasury signature). Returns base64. Used for sponsored
    /// NFT nickname mints.
    static func buildSponsoredInstructionsBase64(
        _ instructions: [TransactionInstruction],
        signers: [KeyPair],
        treasury: PublicKey,
        endpointURL: String
    ) async throws -> String {
        let blockhash = try await fetchLatestBlockhash(endpointURL: endpointURL)
        var transaction = Transaction(instructions: instructions,
                                      recentBlockhash: blockhash, feePayer: treasury)
        try transaction.partialSign(signers: signers)
        return try transaction.serialize(requiredAllSignatures: false).bytes.toBase64()
    }

    /// Plain SOL transfer over the same robust raw-URLSession path (confirmed
    /// commitment) — avoids SolanaSwift's client which throws blockhashNotFound.
    static func sendSOL(
        from keypair: KeyPair,
        to recipientAddress: String,
        lamports: UInt64,
        endpointURL: String
    ) async throws -> String {
        let recipient = try PublicKey(string: recipientAddress)
        guard recipient.bytes.count == PublicKey.numberOfBytes else {
            throw rpcFail(method: "build", "некорректный Solana-адрес получателя (\(recipientAddress))")
        }
        let transferInstruction = SystemProgram.transferInstruction(
            from: keypair.publicKey, to: recipient, lamports: lamports
        )
        let blockhash = try await fetchLatestBlockhash(endpointURL: endpointURL)
        var transaction = Transaction(
            instructions: try priorityInstructions() + [transferInstruction],
            recentBlockhash: blockhash,
            feePayer: keypair.publicKey
        )
        try transaction.sign(signers: [keypair])
        let serialized = try transaction.serialize().bytes.toBase64()
        return try await sendRawTransaction(serialized: serialized, endpointURL: endpointURL)
    }

    /// Marketplace purchase in one atomic transaction: pay the seller, pay the
    /// dev commission, and write a `sold` memo referencing the registry address
    /// (so the lot disappears for everyone scanning it). Zero-lamport transfers
    /// are skipped. Fee payer = buyer.
    static func purchase(
        from keypair: KeyPair,
        seller: String, sellerLamports: UInt64,
        dev: String, devLamports: UInt64,
        registry: String, memoBase64: String,
        endpointURL: String
    ) async throws -> String {
        var instructions = try priorityInstructions()

        func transfer(to address: String, lamports: UInt64) throws {
            guard lamports > 0 else { return }
            let key = try PublicKey(string: address)
            guard key.bytes.count == PublicKey.numberOfBytes else {
                throw rpcFail(method: "build", "некорректный адрес (\(address))")
            }
            instructions.append(SystemProgram.transferInstruction(
                from: keypair.publicKey, to: key, lamports: lamports))
        }
        try transfer(to: seller, lamports: sellerLamports)
        try transfer(to: dev, lamports: devLamports)

        // Memo referencing the registry so the "sold" event lands in its history.
        let registryKey = try PublicKey(string: registry)
        guard registryKey.bytes.count == PublicKey.numberOfBytes else {
            throw rpcFail(method: "build", "некорректный адрес реестра (\(registry))")
        }
        let memoIx = TransactionInstruction(
            keys: [AccountMeta(publicKey: registryKey, isSigner: false, isWritable: false)],
            programId: try PublicKey(string: memoProgramId),
            data: Array(memoBase64.utf8))
        instructions.append(memoIx)

        let blockhash = try await fetchLatestBlockhash(endpointURL: endpointURL)
        var transaction = Transaction(instructions: instructions,
                                      recentBlockhash: blockhash, feePayer: keypair.publicKey)
        try transaction.sign(signers: [keypair])
        let serialized = try transaction.serialize().bytes.toBase64()
        return try await sendRawTransaction(serialized: serialized, endpointURL: endpointURL)
    }

    /// Build, sign and submit an arbitrary instruction list over the robust raw
    /// path (priority fee + confirmed commitment). Used for on-chain NFT mints.
    static func sendInstructions(
        _ instructions: [TransactionInstruction],
        signers: [KeyPair],
        feePayer: PublicKey,
        endpointURL: String
    ) async throws -> String {
        let blockhash = try await fetchLatestBlockhash(endpointURL: endpointURL)
        var transaction = Transaction(instructions: try priorityInstructions() + instructions,
                                      recentBlockhash: blockhash, feePayer: feePayer)
        try transaction.sign(signers: signers)
        let serialized = try transaction.serialize().bytes.toBase64()
        return try await sendRawTransaction(serialized: serialized, endpointURL: endpointURL)
    }

    // MARK: - Real fee estimation

    /// Actual network fee (lamports) for a message via getFeeForMessage —
    /// includes the base signature fee + priority fee. Best-effort.
    static func feeForMessage(_ messageBase64: String, endpointURL: String) async -> UInt64? {
        guard let json = try? await rpcRequest(
            endpointURL: endpointURL, method: "getFeeForMessage",
            params: [messageBase64, ["commitment": "confirmed"]]
        ),
        let result = json["result"] as? [String: Any],
        let value  = result["value"] as? Int, value >= 0
        else { return nil }
        return UInt64(value)
    }

    /// Real fee to mint a nickname (memo `mint:nick:<handle>` to self).
    static func estimateMintFee(from keypair: KeyPair, handle: String, endpointURL: String) async -> UInt64? {
        guard let memoProgram = try? PublicKey(string: memoProgramId),
              let blockhash = try? await fetchLatestBlockhash(endpointURL: endpointURL) else { return nil }
        let memo = Data("mint:nick:\(handle)".utf8).base64EncodedString()
        let memoIx = TransactionInstruction(
            keys: [AccountMeta(publicKey: keypair.publicKey, isSigner: true, isWritable: false)],
            programId: memoProgram, data: Array(memo.utf8)
        )
        let ixs = ((try? priorityInstructions()) ?? []) + [memoIx]
        var tx = Transaction(instructions: ixs, recentBlockhash: blockhash, feePayer: keypair.publicKey)
        guard let msg = try? tx.compileMessage().serialize() else { return nil }
        return await feeForMessage(msg.base64EncodedString(), endpointURL: endpointURL)
    }

    // MARK: - getLatestBlockhash (direct URLSession, avoids SolanaSwift decoder)

    static func fetchLatestBlockhash(endpointURL: String) async throws -> String {
        let json = try await rpcRequest(
            endpointURL: endpointURL,
            method: "getLatestBlockhash",
            params: [["commitment": "confirmed"]]
        )
        guard let result = json["result"] as? [String: Any],
              let value  = result["value"]  as? [String: Any],
              let hash   = value["blockhash"] as? String
        else { throw rpcError(from: json, method: "getLatestBlockhash") }
        return hash
    }

    // MARK: - sendTransaction (direct URLSession, avoids SolanaSwift decoder)

    private static func sendRawTransaction(serialized: String, endpointURL: String) async throws -> String {
        let json = try await rpcRequest(
            endpointURL: endpointURL,
            method: "sendTransaction",
            params: [serialized, ["encoding": "base64", "preflightCommitment": "confirmed"]]
        )
        if let signature = json["result"] as? String { return signature }
        throw rpcError(from: json, method: "sendTransaction")
    }

    // MARK: - Shared helpers

    private static func rpcRequest(
        endpointURL: String,
        method: String,
        params: [Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: endpointURL) else {
            throw rpcFail(method: method, "невалидный URL эндпоинта: \(endpointURL)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let bodyText = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Non-JSON response (rate-limit HTML, gateway error, etc.) — surface it verbatim.
            throw rpcFail(method: method,
                          "HTTP \(status), не-JSON ответ: \(bodyText.prefix(300))")
        }
        return json
    }

    /// Build a descriptive error from a JSON-RPC `error` field. Handles the field
    /// being either the standard object `{code,message}` OR a bare string (some
    /// gateways like Ankr do this), and falls back to dumping the whole payload
    /// so the cause is never swallowed into an opaque "Malformed data".
    private static func rpcError(from json: [String: Any], method: String) -> Error {
        if let err = json["error"] as? [String: Any] {
            let msg  = err["message"] as? String ?? "\(err)"
            let code = err["code"]    as? Int    ?? -1
            return rpcFail(method: method, "RPC error \(code): \(msg)")
        }
        if let errString = json["error"] as? String {
            return rpcFail(method: method, "RPC error: \(errString)")
        }
        return rpcFail(method: method, "неожиданный ответ: \(json)")
    }

    private static func rpcFail(method: String, _ detail: String) -> Error {
        let msg = "\(method) — \(detail)"
        #if DEBUG
        print("⛏️ MemoTransactionBuilder \(msg)")
        #endif
        return NSError(domain: "SolanaRPC", code: 0,
                       userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
