//
//  SubscriptionManager.swift
//  privamesh
//
//  StoreKit 2 store for PrivaMesh+ membership and message packs.
//
//  Messaging is metered: every message is a Solana transaction whose network fee
//  is paid by a shared, app-operated gas wallet (via the relay). Users never hold
//  or spend cryptocurrency. Access to send is granted by Apple IAP:
//    • Auto-renewable subscriptions (Plus / Pro) — a monthly message allowance.
//    • Consumable packs (100 / 500 / 1500) — one-off message credits.
//  Pack credits are mirrored into MessageQuotaService via `onPackPurchased`.
//

import Foundation
import StoreKit

/// Membership tier, derived from the active auto-renewable subscription.
enum PlusTier: String {
    case none, plus, pro

    /// Monthly message allowance sponsored by the tier (0 for `none`).
    /// Caps are sized so the shared gas wallet stays profitable even at elevated
    /// network fees — see the pricing model.
    var monthlyMessages: Int {
        switch self {
        case .none: return 0
        case .plus: return 1200
        case .pro:  return 2000
        }
    }

    /// Membership perks (checkmark, multi-account, free nickname mint).
    var hasCheckmark: Bool { self != .none }
    var maxAccounts: Int { self == .none ? 1 : 3 }
    var freeNicknameMint: Bool { self == .pro }
}

@Observable
final class SubscriptionManager {
    // MARK: - Product catalog

    static let plusProductId = "com.privamesh.plus.monthly"
    static let proProductId  = "com.privamesh.pro.monthly"
    static let subscriptionIds = [plusProductId, proProductId]

    /// Consumable message packs: productID → messages granted.
    static let packMessages: [String: Int] = [
        "com.privamesh.msgs.100": 100,
        "com.privamesh.msgs.500": 500,
        "com.privamesh.msgs.1500": 1500,
    ]

    /// Legacy single-product alias (kept so older call sites compile).
    static var productId: String { plusProductId }

    // MARK: - State

    private(set) var subscriptionProducts: [String: Product] = [:]
    private(set) var packProducts: [String: Product] = [:]

    /// Active membership tier (drives allowance + perks).
    private(set) var tier: PlusTier = .none
    /// True while any paid membership is active.
    var isSubscribed: Bool { tier != .none }

    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// When the current paid period ends (from the verified transaction).
    private(set) var expiryDate: Date?
    /// Whether the subscription renews automatically (from renewal info).
    private(set) var autoRenew = true

    /// Invoked when a consumable pack is purchased, with the messages to credit.
    /// Wired to MessageQuotaService by the app root (on-device mirror).
    var onPackPurchased: ((Int) -> Void)?

    /// Invoked with the pack receipt JWS so the relay can credit its authoritative
    /// server-side balance. Wired to RelayService by the app root.
    var onPackReceipt: ((String) async -> Void)?

    private var updatesTask: Task<Void, Never>?

    /// Transaction IDs already credited, to avoid double-granting a pack that is
    /// delivered via both the purchase result and Transaction.updates.
    private static let processedKey = "privamesh.store.processedTx"
    private var processedTxIDs: Set<UInt64> = {
        let raw = UserDefaults.standard.array(forKey: processedKey) as? [NSNumber] ?? []
        return Set(raw.map { $0.uint64Value })
    }()

    /// Back-compat: the Plus product for existing paywall UI.
    var product: Product? { subscriptionProducts[Self.plusProductId] }

    var expiryText: String {
        guard let expiryDate else { return "" }
        return expiryDate.formatted(date: .abbreviated, time: .omitted)
    }

    /// Whole days left until the current subscription period ends (nil if none).
    var daysRemaining: Int? {
        guard let expiryDate else { return nil }
        let d = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day
        return d.map { max(0, $0) }
    }

    /// Display name of the active tier.
    var tierDisplayName: String {
        switch tier {
        case .pro:  return "PrivaMesh+ Pro"
        case .plus: return "PrivaMesh+ Starter"
        case .none: return ""
        }
    }

    init() {
        updatesTask = Task { await listenForTransactionUpdates() }
        Task {
            await loadProducts()
            await refreshStatus()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Load

    @MainActor
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = Set(Self.subscriptionIds).union(Self.packMessages.keys)
            let products = try await Product.products(for: ids)
            for p in products {
                if Self.packMessages[p.id] != nil { packProducts[p.id] = p }
                else { subscriptionProducts[p.id] = p }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Back-compat alias.
    @MainActor
    func loadProduct() async { await loadProducts() }

    // MARK: - Purchase

    /// Purchase the Plus subscription (back-compat entry point).
    @MainActor
    func purchase() async { await purchase(productId: Self.plusProductId) }

    /// Purchase any product by id (subscription or pack).
    @MainActor
    func purchase(productId: String) async {
        let product = subscriptionProducts[productId] ?? packProducts[productId]
        guard let product else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
                if case .verified(let tx) = verification { await tx.finish() }
                await refreshStatus()
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Restore / Status

    /// Recompute membership tier + expiry from active entitlements.
    @MainActor
    func refreshStatus() async {
        var active: PlusTier = .none
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.revocationDate == nil else { continue }
            if let exp = tx.expirationDate, exp < Date() { continue }   // lapsed
            switch tx.productID {
            case Self.proProductId:
                active = .pro                              // Pro wins over Plus
                expiry = tx.expirationDate
            case Self.plusProductId where active != .pro:
                active = .plus
                expiry = tx.expirationDate
            default:
                break
            }
        }
        tier = active
        expiryDate = expiry

        // Auto-renew flag from the active subscription's renewal info.
        let activeProduct = subscriptionProducts[active == .pro ? Self.proProductId : Self.plusProductId]
        if active != .none, let statuses = try? await activeProduct?.subscription?.status {
            autoRenew = statuses.contains { status in
                if case .verified(let renewal) = status.renewalInfo { return renewal.willAutoRenew }
                return false
            }
        } else {
            autoRenew = false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshStatus()
    }

    /// JWS of the highest active subscription entitlement (Pro > Plus), sent to
    /// the relay so it can verify the monthly allowance server-side. Returns nil
    /// when no subscription is active. (Consumable packs are credited separately.)
    func currentEntitlementJWS() async -> String? {
        var best: (rank: Int, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, tx.revocationDate == nil else { continue }
            if let exp = tx.expirationDate, exp < Date() { continue }
            let rank: Int
            switch tx.productID {
            case Self.proProductId:  rank = 2
            case Self.plusProductId: rank = 1
            default:                 continue
            }
            if best == nil || rank > best!.rank { best = (rank, result.jwsRepresentation) }
        }
        return best?.jws
    }

    // MARK: - Transaction handling

    /// Credit a consumable pack exactly once. Subscriptions are handled by
    /// `refreshStatus`; here we grant pack messages locally AND forward the
    /// receipt to the relay (authoritative balance).
    @MainActor
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result else { return }
        guard let messages = Self.packMessages[tx.productID] else { return }
        guard !processedTxIDs.contains(tx.id) else { return }
        processedTxIDs.insert(tx.id)
        UserDefaults.standard.set(processedTxIDs.map { NSNumber(value: $0) }, forKey: Self.processedKey)
        onPackPurchased?(messages)
        await onPackReceipt?(result.jwsRepresentation)
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            await handle(result)
            if case .verified(let tx) = result { await tx.finish() }
            await refreshStatus()
        }
    }
}
