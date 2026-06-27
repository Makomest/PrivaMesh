//
//  OnChainNFT.swift
//  privamesh
//
//  Real on-chain ownership for avatars/nicknames as SPL tokens (supply 1,
//  decimals 0). Minting via the standard SPL Token program (already on mainnet —
//  no program to deploy). The design id is recorded in a memo ("PNFT1:<id>") in
//  the mint tx, so any device with the seed can rebuild the collection from
//  chain — ownership is portable, not just local UserDefaults.
//
//  Not a Metaplex NFT (won't show with art in external wallets), but ownership
//  is genuinely on-chain and seed-portable.
//

import Foundation
import SolanaSwift

enum OnChainNFT {
    static let memoPrefix = "PNFT1:"
    private static let mintAccountSpan: UInt64 = 82    // SPL Mint account size
    private static let tokenAccountSpan: UInt64 = 165  // SPL token account size

    /// Lamports one mint consumes: mint rent + token-acct rent + a fee margin.
    /// Used for a pre-flight balance check (avoids a cryptic on-chain 0x1 =
    /// ResultWithNegativeLamports when the wallet can't cover the second account).
    static let lamportsPerMint: UInt64 = 1_461_600 + 2_039_280 + 15_000

    // MARK: - Mint

    /// Mint a fresh SPL "NFT" representing `designId` to the owner. Returns the
    /// mint address. Costs ~rent for the mint + ATA (paid by `keypair`).
    @discardableResult
    static func mint(designId: String, keypair: KeyPair, rpc: SolanaRPCService) async throws -> String {
        let owner = keypair.publicKey
        let tokenProgram = TokenProgram.id
        let mintKP = try await KeyPair(network: .mainnetBeta)    // random mint keypair
        let mint = mintKP.publicKey
        // Use a plain token account (fresh keypair) instead of an Associated
        // Token Account — the ATA program rejected our create with custom error
        // 0x1 regardless of layout/idempotency. getTokenAccountsByOwner still
        // returns any token account the wallet owns, so ownership reads work.
        let tokenKP = try await KeyPair(network: .mainnetBeta)
        let tokenAcc = tokenKP.publicKey

        let endpoint = rpc.currentEndpoint.address
        // Fixed rent-exempt minimums (avoid a flaky RPC decoder path).
        let mintRent:  UInt64 = 1_461_600   // 82-byte SPL Mint   (~0.00146 SOL)
        let tokenRent: UInt64 = 2_039_280   // 165-byte token acct (~0.00204 SOL)

        let memoProgram = try PublicKey(string: MemoTransactionBuilder.memoProgramId)
        let memoIx = TransactionInstruction(
            keys: [AccountMeta(publicKey: owner, isSigner: true, isWritable: false)],
            programId: memoProgram,
            data: Array("\(memoPrefix)\(designId)".utf8))

        let instructions: [TransactionInstruction] = [
            SystemProgram.createAccountInstruction(
                from: owner, toNewPubkey: mint, lamports: mintRent,
                space: mintAccountSpan, programId: tokenProgram),
            TokenProgram.initializeMintInstruction(
                mint: mint, decimals: 0, authority: owner, freezeAuthority: nil),
            SystemProgram.createAccountInstruction(
                from: owner, toNewPubkey: tokenAcc, lamports: tokenRent,
                space: tokenAccountSpan, programId: tokenProgram),
            TokenProgram.initializeAccountInstruction(
                account: tokenAcc, mint: mint, owner: owner),
            TokenProgram.mintToInstruction(
                mint: mint, destination: tokenAcc, authority: owner, amount: 1),
            memoIx,
        ]

        _ = try await MemoTransactionBuilder.sendInstructions(
            instructions, signers: [keypair, mintKP, tokenKP], feePayer: owner, endpointURL: endpoint)
        return mint.base58EncodedString
    }

    // MARK: - Read

    /// Design ids the wallet owns on-chain. getTokenAccountsByOwner → supply-1
    /// mints → their PNFT1 mint-memo. Best-effort; returns [] on failure.
    static func ownedDesignIds(owner: String, rpc: SolanaRPCService) async -> [String] {
        guard let mints = await heldNFTMints(owner: owner, endpointURL: rpc.currentEndpoint.address),
              !mints.isEmpty else { return [] }
        var ids: [String] = []
        for mint in mints {
            if let id = await designId(forMint: mint, rpc: rpc) { ids.append(id) }
        }
        return ids
    }

    /// Mints the owner holds with amount == 1 and decimals == 0 (NFT-like).
    private static func heldNFTMints(owner: String, endpointURL: String) async -> [String]? {
        guard let url = URL(string: endpointURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "getTokenAccountsByOwner",
            "params": [owner,
                       ["programId": TokenProgram.id.base58EncodedString],
                       ["encoding": "jsonParsed", "commitment": "confirmed"]]
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? [[String: Any]] else { return nil }

        var mints: [String] = []
        for acc in value {
            guard let account = acc["account"] as? [String: Any],
                  let pdata = account["data"] as? [String: Any],
                  let parsed = pdata["parsed"] as? [String: Any],
                  let info = parsed["info"] as? [String: Any],
                  let mint = info["mint"] as? String,
                  let amount = info["tokenAmount"] as? [String: Any],
                  let uiAmt = amount["amount"] as? String,
                  let decimals = amount["decimals"] as? Int,
                  uiAmt == "1", decimals == 0 else { continue }
            mints.append(mint)
        }
        return mints
    }

    /// The design id recorded in a mint's PNFT1 memo (from its creation tx).
    private static func designId(forMint mint: String, rpc: SolanaRPCService) async -> String? {
        let config = RequestConfiguration(commitment: "confirmed", limit: 20)
        guard let mintKey = try? PublicKey(string: mint),
              let sigs = try? await rpc.client.getSignaturesForAddress(address: mintKey.base58EncodedString, configs: config)
        else { return nil }
        for info in sigs {
            guard let memo = info.memo else { continue }
            let cleaned = memo.hasPrefix("[")
                ? String(memo.drop { $0 != " " }.dropFirst()).trimmingCharacters(in: .whitespaces)
                : memo
            if cleaned.hasPrefix(memoPrefix) { return String(cleaned.dropFirst(memoPrefix.count)) }
        }
        return nil
    }
}
