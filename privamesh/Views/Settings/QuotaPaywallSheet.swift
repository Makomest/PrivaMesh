//
//  QuotaPaywallSheet.swift
//  privamesh
//
//  Shown when the user is out of message credits. Messaging is metered: every
//  message is a Solana transaction whose network fee is paid by the app. Users
//  buy access via Apple IAP — a monthly subscription (Plus/Pro) or a one-off
//  message pack. Auto-dismisses once the purchase restores the ability to send.
//

import SwiftUI
import StoreKit

struct QuotaPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(MessageQuotaService.self) private var quota

    /// Ordered pack product IDs (small → large) for stable display.
    private let packOrder = ["com.privamesh.msgs.100",
                             "com.privamesh.msgs.500",
                             "com.privamesh.msgs.1500"]

    /// Render static sample rows when StoreKit products aren't loaded — used only
    /// to capture App Store review screenshots outside a live StoreKit session.
    var sampleMode = false
    private static let samplePrice: [String: String] = [
        "com.privamesh.plus.monthly": "$5.99", "com.privamesh.pro.monthly": "$9.99",
        "com.privamesh.msgs.100": "$0.99", "com.privamesh.msgs.500": "$3.99",
        "com.privamesh.msgs.1500": "$9.99",
    ]
    private static let sampleName: [String: String] = [
        "com.privamesh.plus.monthly": "PrivaMesh+ Starter", "com.privamesh.pro.monthly": "PrivaMesh+ Pro",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if noProducts {
                    emptyState
                } else {
                    subscriptionSection
                    packSection
                }

                Button {
                    Task { await subscription.restorePurchases() }
                } label: {
                    Text("Восстановить покупки")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accentDeep)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Text("PrivaMesh+ — авто-возобновляемая подписка (1 месяц). Оплата списывается с Apple ID, продлевается автоматически; отмена в любой момент в настройках Apple ID минимум за 24 часа до конца периода. Комиссии сети оплачиваются за вас.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.slate400)
                    .padding(.horizontal, 8)

                // Required for auto-renewable subscriptions (Guideline 3.1.2):
                // functional links to Privacy Policy and Terms of Use (EULA).
                HStack(spacing: 6) {
                    Link("Политика конфиденциальности", destination: URL(string: "https://makomest.github.io/PrivaMesh/privacy-policy.html")!)
                    Text("·").foregroundStyle(Theme.slate400)
                    Link("Условия использования (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.system(size: 11, weight: .medium))
                .tint(Theme.accentDeep)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
            }
            .padding(24)
        }
        .background(PastelBackground().ignoresSafeArea())
        .task { if subscription.subscriptionProducts.isEmpty { await subscription.loadProducts() } }
        // Close automatically once a purchase restores sending.
        .onChange(of: quota.remaining) { _, new in if new > 0 { dismiss() } }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.slate400)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    // MARK: - Sections

    /// No products available (StoreKit not loaded yet or IAP not live).
    private var noProducts: Bool {
        !sampleMode && subscription.subscriptionProducts.isEmpty && subscription.packProducts.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if subscription.isLoading {
                ProgressView().tint(Theme.accent)
                Text("Загрузка предложений…")
                    .font(.system(size: 14)).foregroundStyle(Theme.slate500)
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 28)).foregroundStyle(Theme.slate400)
                Text("Предложения недоступны")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.slate800)
                Text("Проверь соединение и повтори.")
                    .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                Button {
                    Task { await subscription.loadProducts() }
                } label: {
                    Text("Повторить")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Theme.accentGradient).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
                .padding(.top, 12)
            Text(quota.remaining > 0 ? "Больше сообщений" : "Сообщения закончились")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.slate800)
            Text("Осталось: \(quota.remaining)")
                .font(.system(size: 14))
                .foregroundStyle(Theme.slate500)
        }
    }

    private var subscriptionSection: some View {
        VStack(spacing: 12) {
            sectionTitle("Подписка")
            if subscription.isSubscribed {
                activeSubscriptionRow
            } else {
                subscriptionButton(id: SubscriptionManager.plusProductId,
                                   tier: .plus, highlight: false)
                subscriptionButton(id: SubscriptionManager.proProductId,
                                   tier: .pro, highlight: true)
            }
        }
    }

    /// Greyed-out status row shown once a subscription is active — no re-purchase,
    /// only pack purchases remain. Shows days left in the current period.
    private var activeSubscriptionRow: some View {
        let days = subscription.daysRemaining
        let daysText = days.map { String(localized: "Активна · осталось \($0) дн.") }
            ?? String(localized: "Активна")
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.tierDisplayName)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.slate500)
                Text(daysText)
                    .font(.system(size: 12)).foregroundStyle(Theme.slate400)
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18)).foregroundStyle(Theme.positive)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Theme.glass)
            .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1)))
        .opacity(0.7)
    }

    private var packSection: some View {
        VStack(spacing: 12) {
            sectionTitle("Разовые пакеты")
            ForEach(packOrder, id: \.self) { id in
                let messages = SubscriptionManager.packMessages[id] ?? 0
                let title = String(localized: "\(messages) сообщений")
                if let product = subscription.packProducts[id] {
                    purchaseRow(title: title, subtitle: nil,
                                price: product.displayPrice, highlight: false) {
                        Task { await subscription.purchase(productId: id) }
                    }
                } else if sampleMode {
                    purchaseRow(title: title, subtitle: nil,
                                price: Self.samplePrice[id] ?? "", highlight: false) {}
                }
            }
        }
    }

    // MARK: - Rows

    /// Perks listed on each subscription card.
    private func perks(for tier: PlusTier) -> [String] {
        var list = [
            String(localized: "\(tier.monthlyMessages) сообщений в месяц"),
            String(localized: "Галочка верификации на аккаунте"),
            String(localized: "До 3 аккаунтов на устройстве"),
        ]
        return list
    }

    private func subscriptionButton(id: String, tier: PlusTier, highlight: Bool) -> some View {
        Group {
            if let product = subscription.subscriptionProducts[id] {
                subscriptionCard(name: product.displayName,
                                 price: String(localized: "\(product.displayPrice)/мес"),
                                 tier: tier, highlight: highlight) {
                    Task { await subscription.purchase(productId: id) }
                }
            } else if sampleMode {
                subscriptionCard(name: Self.sampleName[id] ?? "",
                                 price: String(localized: "\(Self.samplePrice[id] ?? "")/мес"),
                                 tier: tier, highlight: highlight) {}
            }
        }
    }

    private func subscriptionCard(name: String, price: String, tier: PlusTier,
                                  highlight: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(highlight ? .white : Theme.slate800)
                    Spacer()
                    if subscription.isLoading {
                        ProgressView().tint(highlight ? .white : Theme.accent)
                    } else {
                        Text(price)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(highlight ? .white : Theme.accentDeep)
                    }
                }
                ForEach(perks(for: tier), id: \.self) { perk in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(highlight ? .white.opacity(0.9) : Theme.accent)
                        Text(perk)
                            .font(.system(size: 13))
                            .foregroundStyle(highlight ? .white.opacity(0.95) : Theme.slate500)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if highlight {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.glass)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.glassStroke, lineWidth: 1))
                }
            }
            .shadow(color: highlight ? Theme.accent.opacity(0.35) : .clear, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(subscription.isLoading)
    }

    private func purchaseRow(title: String, subtitle: String?, price: String,
                             highlight: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(highlight ? .white : Theme.slate800)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(highlight ? .white.opacity(0.85) : Theme.slate500)
                    }
                }
                Spacer()
                if subscription.isLoading {
                    ProgressView().tint(highlight ? .white : Theme.accent)
                } else {
                    Text(price)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(highlight ? .white : Theme.accentDeep)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background {
                if highlight {
                    Capsule().fill(Theme.accentGradient)
                } else {
                    Capsule().fill(Theme.glass)
                        .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
                }
            }
            .shadow(color: highlight ? Theme.accent.opacity(0.35) : .clear, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(subscription.isLoading)
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(LocalizedStringKey(text))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.slate500)
            Spacer()
        }
    }
}
