//
//  CoverTrafficService.swift
//  privamesh
//
//  Decoy traffic. When enabled, periodically sends a cover (dummy) message on a
//  random established conversation at randomized intervals. Each decoy is a real
//  DR/stealth message carrying random bytes — on-chain it's indistinguishable
//  from a genuine message, so an observer can't tell WHEN you actually talk.
//
//  Cost: each decoy is a real Solana memo tx (fee). Off by default.
//

import Foundation
import SwiftData
import SolanaSwift

@Observable
final class CoverTrafficService {
    private static let enabledKey = "privamesh.coverTraffic.enabled"

    /// Randomized gap between decoy attempts (seconds). Wide + jittered so the
    /// timing carries no signal.
    private static let minGap: UInt64 = 45
    private static let maxGap: UInt64 = 180

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    private var task: Task<Void, Never>?

    func start(myAddress: String, wallet: WalletManager, gasWallet: GasWalletService,
               identity: MessagingIdentityManager,
               rpc: SolanaRPCService, sender: MessageSender, context: ModelContext) {
        stop()
        guard isEnabled else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let gap = UInt64.random(in: Self.minGap...Self.maxGap)
                try? await Task.sleep(for: .seconds(gap))
                guard !Task.isCancelled, self?.isEnabled == true else { break }
                await self?.tick(myAddress: myAddress, wallet: wallet, gasWallet: gasWallet,
                                 identity: identity, rpc: rpc, sender: sender, context: context)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Restart after the toggle changes.
    func refresh(myAddress: String, wallet: WalletManager, gasWallet: GasWalletService,
                 identity: MessagingIdentityManager,
                 rpc: SolanaRPCService, sender: MessageSender, context: ModelContext) {
        start(myAddress: myAddress, wallet: wallet, gasWallet: gasWallet, identity: identity,
              rpc: rpc, sender: sender, context: context)
    }

    @MainActor
    private func tick(myAddress: String, wallet: WalletManager, gasWallet: GasWalletService,
                      identity: MessagingIdentityManager,
                      rpc: SolanaRPCService, sender: MessageSender, context: ModelContext) async {
        let desc = FetchDescriptor<Contact>()
        let eligible = ((try? context.fetch(desc)) ?? []).filter {
            !$0.isSelf && $0.ownerAddress == myAddress
                && $0.stealthRoot != nil && $0.sessionData != nil
        }
        guard let contact = eligible.randomElement(),
              let keyPair = try? await wallet.currentKeyPair() else { return }
        // Don't burn failed txs when the gas wallet can't cover a fee.
        if await gasWallet.needsTopUp(rpc: rpc) { return }
        let payer = await gasWallet.feePayer(fallback: keyPair)
        await sender.sendCover(to: contact, senderKeyPair: payer,
                               identity: identity, rpc: rpc, context: context)
    }
}
