//
//  WalletBalanceService.swift
//  privamesh
//

import Foundation
import SolanaSwift

@Observable
final class WalletBalanceService {
    enum State {
        case idle
        case loading
        case loaded(lamports: UInt64, updatedAt: Date)
        case error(String)
    }

    static let lamportsPerSOL: UInt64 = 1_000_000_000

    var state: State = .idle

    var balanceLamports: UInt64? {
        if case let .loaded(lamports, _) = state { return lamports }
        return nil
    }

    var balanceSOL: Decimal? {
        guard let lamports = balanceLamports else { return nil }
        return Decimal(lamports) / Decimal(Self.lamportsPerSOL)
    }

    var lastUpdated: Date? {
        if case let .loaded(_, updatedAt) = state { return updatedAt }
        return nil
    }

    /// Fetch balance for a public key. Rotates RPC on failure.
    @MainActor
    func refresh(publicKey: String, rpc: SolanaRPCService) async {
        // Keep showing the current balance while refreshing — only show the
        // spinner if we have nothing yet, so the value doesn't flicker away.
        var priorLamports: UInt64?
        var priorUpdatedAt: Date?
        if case let .loaded(l, u) = state { priorLamports = l; priorUpdatedAt = u }
        if priorLamports == nil { state = .loading }

        var attempts = rpc.endpoints.count
        while attempts > 0 {
            if Task.isCancelled { return }   // superseded by a newer refresh — keep current state
            do {
                let lamports = try await rpc.client.getBalance(account: publicKey, commitment: "confirmed")
                state = .loaded(lamports: lamports, updatedAt: Date())
                return
            } catch {
                // A cancelled request is not a failure (view churn / tab switch).
                // Don't blow away the balance with a red "cancelled".
                if Self.isCancellation(error) || Task.isCancelled { return }
                attempts -= 1
                if attempts == 0 {
                    if let priorLamports {
                        state = .loaded(lamports: priorLamports, updatedAt: priorUpdatedAt ?? Date())
                    } else {
                        state = .error("Не удалось обновить баланс")
                    }
                } else {
                    rpc.rotate()
                }
            }
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
