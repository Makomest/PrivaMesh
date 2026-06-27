//
//  SubscriptionManager.swift
//  privamesh
//
//  StoreKit 2 subscription manager for PrivaMesh+ premium tier.
//  Premium is a real Apple auto-renewable subscription (the NFT market still
//  pays in SOL via the wallet — only the membership goes through Apple IAP).
//

import Foundation
import StoreKit

@Observable
final class SubscriptionManager {
    /// Auto-renewable subscription product, defined in App Store Connect and in
    /// the bundled StoreKit configuration (privamesh.storekit) for local testing.
    static let productId = "com.privamesh.plus.monthly"

    private(set) var product: Product?
    private(set) var isSubscribed = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// When the current paid period ends (from the verified transaction).
    private(set) var expiryDate: Date?
    /// Whether the subscription renews automatically (from StoreKit renewal info).
    private(set) var autoRenew = true

    private var updatesTask: Task<Void, Never>?

    var expiryText: String {
        guard let expiryDate else { return "" }
        return expiryDate.formatted(date: .abbreviated, time: .omitted)
    }

    init() {
        updatesTask = Task { await listenForTransactionUpdates() }
        Task {
            await loadProduct()
            await refreshStatus()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Load

    @MainActor
    func loadProduct() async {
        isLoading = true
        do {
            let products = try await Product.products(for: [Self.productId])
            product = products.first
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Purchase

    @MainActor
    func purchase() async {
        guard let product else { return }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let tx = try verification.payloadValue
                await tx.finish()
                await refreshStatus()
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Restore / Status

    /// Active entitlement → drives isSubscribed + expiry + auto-renew.
    @MainActor
    func refreshStatus() async {
        var active = false
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.productID == Self.productId,
                  tx.revocationDate == nil else { continue }
            if let exp = tx.expirationDate, exp < Date() { continue }   // lapsed
            active = true
            expiry = tx.expirationDate
        }
        isSubscribed = active
        expiryDate = expiry

        // Auto-renew flag from the subscription's renewal info.
        if active, let statuses = try? await product?.subscription?.status {
            for status in statuses {
                if case .verified(let renewal) = status.renewalInfo {
                    autoRenew = renewal.willAutoRenew
                }
            }
        } else {
            autoRenew = false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshStatus()
    }

    // MARK: - Transaction listener

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let tx) = result else { continue }
            await tx.finish()
            await refreshStatus()
        }
    }
}
