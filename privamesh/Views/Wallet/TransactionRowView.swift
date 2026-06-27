//
//  TransactionRowView.swift
//  privamesh
//
//  Shared transaction row used in Wallet + Home: shows type (message / sent /
//  received), SOL amount, USD-at-time, signature; tap opens Solscan.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TransactionRowView: View {
    let tx: TransactionHistoryService.TxRow

    /// Plain decimal (no scientific notation), trimmed.
    static func formatSOL(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 9
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.9f", value)
    }

    // MARK: - Category presentation
    static func icon(for c: TransactionHistoryService.TxRow.Kind) -> String {
        switch c {
        case .sent:     return "arrow.up.right"
        case .received: return "arrow.down.left"
        case .message:  return "lock.fill"
        case .nftMint:  return "sparkles"
        case .market:   return "bag.fill"
        case .profile:  return "person.crop.circle.badge.checkmark"
        }
    }
    static func tint(for c: TransactionHistoryService.TxRow.Kind) -> Color {
        switch c {
        case .sent:     return Theme.negative
        case .received: return Theme.positive
        case .message:  return Theme.accentDeep
        case .nftMint:  return Color(red: 168/255, green: 85/255, blue: 247/255)
        case .market:   return Color(red: 245/255, green: 158/255, blue: 11/255)
        case .profile:  return Theme.accentDeep
        }
    }
    static func title(for c: TransactionHistoryService.TxRow.Kind) -> LocalizedStringKey {
        switch c {
        case .sent:     return "Отправлено"
        case .received: return "Получено"
        case .message:  return "Сообщение"
        case .nftMint:  return "Минт NFT"
        case .market:   return "Маркет"
        case .profile:  return "Публикация профиля"
        }
    }

    var body: some View {
        Button {
            #if os(iOS)
            if let url = URL(string: "https://solscan.io/tx/\(tx.signature)") {
                UIApplication.shared.open(url)
            }
            #endif
        } label: {
            let incoming = (tx.amountLamports ?? 0) > 0
            let icon = tx.isError ? "xmark" : Self.icon(for: tx.category)
            let tint = tx.isError ? Theme.negative : Self.tint(for: tx.category)
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Self.title(for: tx.category))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.slate800)
                        if tx.fromGas {
                            Text("газ")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accentDeep)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accentDeep.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(tx.shortSig)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.slate400)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let sol = tx.amountSOL {
                        Text("\(incoming ? "+" : "−")\(Self.formatSOL(abs(sol))) SOL")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(incoming ? Theme.positive : Theme.negative)
                        if let usd = tx.usdAtTime {
                            Text(usd < 0.01 ? "≈ < $0.01" : String(format: "≈ $%.2f", usd))
                                .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                        }
                    } else if let date = tx.date {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                    }
                    if tx.amountSOL != nil, let date = tx.date {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10)).foregroundStyle(Theme.slate300)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Reusable page navigator (‹ X / Y ›) for paged transaction lists.
struct PageBar: View {
    @Binding var page: Int
    let pageCount: Int

    var body: some View {
        if pageCount > 1 {
            HStack(spacing: 16) {
                Button { if page > 0 { page -= 1 } } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(page > 0 ? Theme.accentDeep : Theme.slate300)
                }
                .disabled(page == 0).buttonStyle(.plain)

                Text("\(page + 1) / \(pageCount)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.slate500)

                Button { if page < pageCount - 1 { page += 1 } } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(page < pageCount - 1 ? Theme.accentDeep : Theme.slate300)
                }
                .disabled(page >= pageCount - 1).buttonStyle(.plain)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
