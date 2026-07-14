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
                        row(icon: "number", title: "ID сообщения", value: shortSig, mono: true)
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

    // Cost is expressed in messages, not SOL: the user pays via Apple IAP, and
    // the network fee is sponsored by the app. Outgoing = 1 message; incoming
    // cost you nothing.
    private var costValue: String {
        msg.isOutgoing ? String(localized: "1 сообщение") : String(localized: "бесплатно")
    }

    private var costSubtitle: String? {
        msg.isOutgoing ? String(localized: "Комиссия сети оплачена приложением") : nil
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
