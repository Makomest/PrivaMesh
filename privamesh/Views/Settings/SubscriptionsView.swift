//
//  SubscriptionsView.swift
//  privamesh
//
//  PrivaMesh+ paywall screen using StoreKit 2.
//

import SwiftUI
import StoreKit

struct SubscriptionsView: View {
    @Environment(SubscriptionManager.self) private var sub
    @Environment(\.dismiss) private var dismiss

    private let features: [(String, String)] = [
        ("lock.shield.fill",   "End-to-end encrypted messages"),
        ("photo.fill",         "Encrypted photo sharing via Arweave"),
        ("person.2.fill",      "Multi-account support"),
        ("at",                 "Solana Name Service (.sol) nicknames"),
        ("bell.badge.fill",    "Priority message polling"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    VStack(spacing: 24) {
                        heroSection
                        featureList
                        priceSection
                        actionButtons
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("PrivaMesh+")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accentDeep)
                }
            }
            #endif
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentGradient)
            Text("PrivaMesh+")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.slate800)
            Text("Full decentralized privacy, unlocked.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(features, id: \.0) { icon, label in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accentDeep)
                        .frame(width: 28)
                    Text(LocalizedStringKey(label))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.slate800)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.positive)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                if icon != features.last?.0 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusLarge))
    }

    private var priceSection: some View {
        VStack(spacing: 4) {
            if sub.isLoading {
                ProgressView().tint(Theme.accent)
            } else if let product = sub.product {
                Text(product.displayPrice)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.slate800)
                Text("per month · cancel any time")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.slate400)
            } else {
                Text("Loading pricing…")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.slate400)
            }
            if let error = sub.errorMessage {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.negative)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if sub.isSubscribed {
                Label("You're subscribed!", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.positive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
            } else {
                Button {
                    Task { await sub.purchase() }
                } label: {
                    Group {
                        if sub.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Subscribe to PrivaMesh+")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
                .disabled(sub.isLoading || sub.product == nil)

                Button("Restore Purchases") {
                    Task { await sub.restorePurchases() }
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentDeep)
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    SubscriptionsView()
        .environment(SubscriptionManager())
}
