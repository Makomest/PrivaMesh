//
//  SendSOLService.swift
//  privamesh
//

import Foundation
import SolanaSwift

@Observable
final class SendSOLService {
    enum State {
        case idle
        case sending
        case success(signature: String)
        case failure(message: String)
    }

    var state: State = .idle

    /// Estimated network fee in lamports (Solana base fee is 5000 lamports/signature).
    static let estimatedFeeLamports: UInt64 = 5000

    @MainActor
    func send(
        from keypair: KeyPair,
        to recipient: String,
        amountSOL: Decimal,
        rpc: SolanaRPCService
    ) async {
        state = .sending

        let lamportsDecimal = amountSOL * Decimal(WalletBalanceService.lamportsPerSOL)
        let lamportsNumber = NSDecimalNumber(decimal: lamportsDecimal).uint64Value

        guard lamportsNumber > 0 else {
            state = .failure(message: "Сумма должна быть больше 0")
            return
        }

        var attempts = rpc.endpoints.count
        while attempts > 0 {
            do {
                // Same robust raw path as messages (confirmed commitment) —
                // SolanaSwift's client threw APIClientError 5 (blockhashNotFound).
                let signature = try await MemoTransactionBuilder.sendSOL(
                    from: keypair,
                    to: recipient,
                    lamports: lamportsNumber,
                    endpointURL: rpc.currentEndpoint.address
                )
                state = .success(signature: signature)
                return
            } catch {
                attempts -= 1
                if attempts == 0 {
                    state = .failure(message: error.localizedDescription)
                } else {
                    rpc.rotate()
                }
            }
        }
    }

    func reset() {
        state = .idle
    }
}
