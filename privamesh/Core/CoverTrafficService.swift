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
    /// timing carries no signal. Sized for the metered model: ~6.5 min average →
    /// roughly 9 decoy messages per hour of active use, each billed to the user's
    /// message balance.
    private static let minGap: UInt64 = 180
    private static let maxGap: UInt64 = 600

    /// Approximate decoys per active hour, for the settings description.
    static let approxPerHour = 9

    /// Message quota. Each decoy is a real sponsored message and is charged to the
    /// user's balance; decoys pause when the balance runs out. Set by the app root.
    weak var quota: MessageQuotaService?

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
        // Each decoy is a real sponsored message — pause when the balance is empty
        // so cover traffic never fails or silently eats a paid allowance the user
        // expects for real messages.
        if let quota, !quota.canSend { return }
        let payer = await gasWallet.feePayer(fallback: keyPair)
        await sender.sendCover(to: contact, senderKeyPair: payer,
                               identity: identity, rpc: rpc, context: context)
        if case .success = sender.state { quota?.consume() }
    }
}
