//
//  TransactionHistoryService.swift
//  privamesh
//

import Foundation
import SolanaSwift

@Observable
final class TransactionHistoryService {
    struct TxRow: Identifiable {
        let id: String       // signature
        let signature: String
        let date: Date?
        let isError: Bool
        let memo: String?
        /// A message tx carries an encrypted memo; everything else is a payment.
        var isMessage: Bool { (memo?.isEmpty == false) }

        /// What the SOL was spent on / where it came from — categorised by the
        /// memo prefix (mints, market, profile publish) or direction.
        enum Kind { case sent, received, message, nftMint, market, profile }
        private var cleanedMemo: String? {
            guard let memo, !memo.isEmpty else { return nil }
            return memo.hasPrefix("[")
                ? String(memo.drop { $0 != " " }.dropFirst()).trimmingCharacters(in: .whitespaces)
                : memo
        }
        var category: Kind {
            if let m = cleanedMemo, !m.isEmpty {
                if m.hasPrefix("PNFT1:") { return .nftMint }
                if m.hasPrefix("PMKT1:") { return .market }
                if m.hasPrefix("PDIR1:") { return .profile }
                return .message
            }
            return (amountLamports ?? 0) > 0 ? .received : .sent
        }
        /// SOL credited (+) / debited (−) to us, in lamports. Payment rows only.
        var amountLamports: Int?
        /// USD value of `amountLamports` at the tx date (historical price).
        var usdAtTime: Double?
        /// Paid by the gas (fee) wallet, not the main wallet.
        var fromGas: Bool = false

        var shortSig: String {
            let s = signature
            guard s.count > 16 else { return s }
            return String(s.prefix(8)) + "…" + String(s.suffix(4))
        }
        var amountSOL: Double? {
            guard let l = amountLamports else { return nil }
            return Double(l) / 1_000_000_000
        }
    }

    enum State {
        case idle
        case loading
        case loaded([TxRow])
        case error(String)
    }

    var state: State = .idle

    var transactions: [TxRow] {
        if case let .loaded(rows) = state { return rows }
        return []
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    /// More pages may exist (last fetch filled the page size).
    private(set) var canLoadMore = false
    private(set) var isLoadingMore = false

    private static let pageSize = 20

    @MainActor
    func refresh(publicKey: String, rpc: SolanaRPCService, price: SOLPriceService? = nil,
                 gasAddress: String? = nil) async {
        // Keep showing existing rows while refreshing; only spin if empty.
        let priorRows = transactions
        if priorRows.isEmpty { state = .loading }
        let config = RequestConfiguration(commitment: "confirmed", limit: Self.pageSize)

        var attempts = rpc.endpoints.count
        while attempts > 0 {
            if Task.isCancelled { return }
            do {
                let sigs = try await rpc.client.getSignaturesForAddress(
                    address: publicKey,
                    configs: config
                )
                var rows = sigs.map { info in
                    TxRow(
                        id: info.signature,
                        signature: info.signature,
                        date: info.blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                        isError: info.err != nil,
                        memo: info.memo
                    )
                }
                canLoadMore = sigs.count >= Self.pageSize
                // Merge the gas wallet's message-fee txs (it pays for messages, so
                // they live in ITS history, not the main wallet's).
                rows = await mergingGasRows(into: rows, gasAddress: gasAddress,
                                            mainAddress: publicKey, rpc: rpc)
                state = .loaded(rows)
                // Enrich payment rows (no memo) with amount + historical USD.
                await enrichPayments(&rows, myAddress: publicKey,
                                     endpointURL: rpc.currentEndpoint.address, price: price)
                if !Task.isCancelled { state = .loaded(rows) }
                return
            } catch {
                if WalletBalanceService.isCancellation(error) || Task.isCancelled { return }
                attempts -= 1
                if attempts == 0 {
                    if priorRows.isEmpty {
                        state = .error("Не удалось загрузить историю")
                    } else {
                        state = .loaded(priorRows)
                    }
                } else {
                    rpc.rotate()
                }
            }
        }
    }

    /// Fetch the gas wallet's recent txs (message-fee payments), tag them, and
    /// merge into the main rows (de-duped, newest first).
    @MainActor
    private func mergingGasRows(into rows: [TxRow], gasAddress: String?,
                               mainAddress: String, rpc: SolanaRPCService) async -> [TxRow] {
        guard let gas = gasAddress, !gas.isEmpty, gas != mainAddress else { return rows }
        let config = RequestConfiguration(commitment: "confirmed", limit: Self.pageSize)
        guard let sigs = try? await rpc.client.getSignaturesForAddress(address: gas, configs: config) else { return rows }
        let known = Set(rows.map(\.signature))
        let gasRows = sigs.compactMap { info -> TxRow? in
            guard !known.contains(info.signature) else { return nil }
            return TxRow(id: info.signature, signature: info.signature,
                         date: info.blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                         isError: info.err != nil, memo: info.memo, fromGas: true)
        }
        return (rows + gasRows).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Append the next page of older transactions (cursor = last loaded signature).
    @MainActor
    func loadMore(publicKey: String, rpc: SolanaRPCService, price: SOLPriceService? = nil) async {
        guard case let .loaded(existing) = state,
              let cursor = existing.last?.signature,
              canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let config = RequestConfiguration(commitment: "confirmed", limit: Self.pageSize, before: cursor)
        var attempts = rpc.endpoints.count
        while attempts > 0 {
            if Task.isCancelled { return }
            do {
                let sigs = try await rpc.client.getSignaturesForAddress(address: publicKey, configs: config)
                var newRows = sigs.map { info in
                    TxRow(id: info.signature, signature: info.signature,
                          date: info.blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                          isError: info.err != nil, memo: info.memo)
                }
                canLoadMore = sigs.count >= Self.pageSize
                // De-dup defensively against the cursor row, then append.
                let known = Set(existing.map(\.signature))
                newRows.removeAll { known.contains($0.signature) }
                var merged = existing + newRows
                state = .loaded(merged)
                await enrichPayments(&merged, myAddress: publicKey,
                                     endpointURL: rpc.currentEndpoint.address, price: price)
                if !Task.isCancelled { state = .loaded(merged) }
                return
            } catch {
                if WalletBalanceService.isCancellation(error) || Task.isCancelled { return }
                attempts -= 1
                if attempts == 0 { return }
                rpc.rotate()
            }
        }
    }

    /// Fill the SOL delta + historical USD for every row (so mints/market/chat
    /// spends show how much they cost, not just plain transfers).
    @MainActor
    private func enrichPayments(_ rows: inout [TxRow], myAddress: String,
                               endpointURL: String, price: SOLPriceService?) async {
        for i in rows.indices where !rows[i].isError && rows[i].amountLamports == nil {
            guard let delta = await Self.fetchDelta(signature: rows[i].signature,
                                                    myAddress: myAddress, endpointURL: endpointURL),
                  delta != 0 else { continue }
            rows[i].amountLamports = delta
            if let price, let date = rows[i].date,
               let usd = await price.historicalUSD(on: date) {
                rows[i].usdAtTime = abs(Double(delta) / 1_000_000_000) * usd
            }
        }
    }

    /// Lamports credited (+) / debited (−) to `myAddress` in a transaction.
    private static func fetchDelta(signature: String, myAddress: String, endpointURL: String) async -> Int? {
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
              let meta    = result["meta"] as? [String: Any],
              let pre     = meta["preBalances"]  as? [Int],
              let post    = meta["postBalances"] as? [Int],
              let tx      = result["transaction"] as? [String: Any],
              let message = tx["message"] as? [String: Any],
              let keys    = message["accountKeys"] as? [String],
              let idx     = keys.firstIndex(of: myAddress),
              idx < pre.count, idx < post.count
        else { return nil }
        return post[idx] - pre[idx]
    }
}
