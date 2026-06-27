//
//  MessageInfoSheet.swift
//  privamesh
//
//  Long-press a message to see what it cost, how long it took to land on
//  Solana, and a link to open the transaction in a block explorer.
//

import SwiftUI

struct MessageInfoSheet: View {
    let msg: ChatMessage
    let solPrice: SOLPriceService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// A real Solana signature only exists once the tx confirmed.
    private var hasSignature: Bool {
        msg.status == "sent" || msg.status == "received"
    }

    private var explorerURL: URL? {
        URL(string: "https://solscan.io/tx/\(msg.id)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    row(icon: "dollarsign.circle.fill", title: "Стоимость", value: costValue, subtitle: costSubtitle)
                    row(icon: "timer", title: "Время доставки", value: deliveryValue)
                    row(icon: "paperplane.fill", title: "Отправлено",
                        value: msg.sentAt.formatted(date: .abbreviated, time: .standard))
                    row(icon: "checkmark.seal.fill", title: "Статус", value: statusValue)
                    if hasSignature {
                        row(icon: "number", title: "Подпись", value: shortSig, mono: true)
                    }

                    if hasSignature, let url = explorerURL {
                        Button { openURL(url) } label: {
                            Label("Открыть в Solana Explorer", systemImage: "arrow.up.right.square")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Theme.accentGradient)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(PastelBackground())
            .navigationTitle("О сообщении")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(Theme.accentDeep)
                }
            }
        }
    }

    // MARK: - Row

    private func row(icon: String, title: String, value: String, subtitle: String? = nil, mono: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentDeep)
                .frame(width: 24)
            Text(LocalizedStringKey(title))
                .font(.system(size: 14))
                .foregroundStyle(Theme.slate600)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .medium, design: mono ? .monospaced : .default))
                    .foregroundStyle(Theme.slate700)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.slate400)
                }
            }
        }
        .padding(14)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Values

    private var costValue: String {
        guard let lamports = msg.feeLamports else {
            return msg.isOutgoing ? "—" : String(localized: "оплачено отправителем")
        }
        let sol = Decimal(lamports) / Decimal(1_000_000_000)
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 9
        let solStr = f.string(from: NSDecimalNumber(decimal: sol)) ?? "\(sol)"
        return "\(solStr) SOL"
    }

    private var costSubtitle: String? {
        guard let lamports = msg.feeLamports else { return nil }
        let sol = Decimal(lamports) / Decimal(1_000_000_000)
        if let usd = solPrice.usdValue(sol: sol) {
            let usdStr = String(format: "%.4f", usd)
            return String(localized: "≈ $\(usdStr) · \(lamports) лампортов")
        }
        return String(localized: "\(lamports) лампортов")
    }

    private var deliveryValue: String {
        guard let s = msg.deliverySeconds else {
            return msg.isOutgoing ? "—" : String(localized: "получено по сети")
        }
        let secStr = String(format: "%.1f", s)
        return String(localized: "\(secStr) с")
    }

    private var statusValue: String {
        switch msg.status {
        case "sending":  return String(localized: "Отправляется…")
        case "sent":     return String(localized: "Доставлено")
        case "received": return String(localized: "Получено")
        case "failed":   return String(localized: "Ошибка")
        default:         return msg.status
        }
    }

    private var shortSig: String {
        guard msg.id.count > 14 else { return msg.id }
        return msg.id.prefix(7) + "…" + msg.id.suffix(7)
    }
}
