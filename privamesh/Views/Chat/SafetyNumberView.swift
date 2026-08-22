//
//  SafetyNumberView.swift
//  privamesh
//
//  Compare a 60-digit number with the other person, out of band, and mark the
//  contact verified if it matches.
//
//  Two ways to compare, because both come up: read the digits aloud on a call, or
//  scan each other's code when you are in the same room. The scan does the
//  comparison for you and says plainly whether it matched — a screen that shows
//  two codes and leaves the user to eyeball them is how people end up "verifying"
//  things they never actually checked.
//

import SwiftUI
import SwiftData

struct SafetyNumberView: View {
    let contact: Contact

    @Environment(MessagingIdentityManager.self) private var identity
    @Environment(WalletManager.self) private var wallet
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var scanResult: ScanResult?

    private enum ScanResult { case match, mismatch }

    private var myAddress: String {
        if case let .ready(pk) = wallet.state { return pk }
        return ""
    }

    /// Both sides derive this independently; it only matches if the keys match.
    private var number: String? {
        guard let mine = try? identity.prekeyBundle() else { return nil }
        return SafetyNumber.digits(myBundle: mine, myAddress: myAddress,
                                   theirBundleBase64: contact.prekeyBundleBase64,
                                   theirAddress: contact.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        if let number {
                            digitsCard(number)
                            qrCard(number)
                            compareCard(number)
                            verifiedCard
                        } else {
                            unavailableCard
                        }
                        explainer
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Проверить контакт")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }.foregroundStyle(Theme.accentDeep)
                }
            }
            .sheet(isPresented: $showScanner) { scannerSheet }
            #endif
        }
    }

    // MARK: - Cards

    private func digitsCard(_ number: String) -> some View {
        VStack(spacing: 10) {
            Text("Ваш общий номер")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.slate600)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(SafetyNumber.formatted(number))
                .accessibilityIdentifier("safetyNumberDigits")
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.slate800)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func qrCard(_ number: String) -> some View {
        VStack(spacing: 10) {
            QRCodeView(text: SafetyNumber.qrPayload(number), size: 190)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Покажи этот код собеседнику")
                .font(.system(size: 11)).foregroundStyle(Theme.slate500)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func compareCard(_ number: String) -> some View {
        VStack(spacing: 12) {
            #if os(iOS)
            Button { scanResult = nil; showScanner = true } label: {
                Label("Сканировать код собеседника", systemImage: "qrcode.viewfinder")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Theme.accentGradient).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            #endif

            if let scanResult {
                HStack(spacing: 8) {
                    Image(systemName: scanResult == .match ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(scanResult == .match ? Theme.positive : Theme.negative)
                    Text(LocalizedStringKey(scanResult == .match
                         ? "Номера совпали"
                         : "Номера НЕ совпали. Не переписывайся, пока не разберёшься."))
                        .font(.system(size: 13))
                        .foregroundStyle(scanResult == .match ? Theme.positive : Theme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private var verifiedCard: some View {
        Toggle(isOn: Binding(
            get: { contact.isVerified },
            set: { on in
                contact.isVerified = on
                contact.verifiedAt = on ? Date() : nil
                try? context.save()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Отметить как проверенный").font(.system(size: 14)).foregroundStyle(Theme.slate800)
                Text(LocalizedStringKey(contact.isVerified && contact.verifiedAt != nil
                     ? "Проверен \(contact.verifiedAt!.formatted(date: .abbreviated, time: .shortened))"
                     : "Ставится вручную, после того как номера совпали"))
                    .font(.system(size: 11)).foregroundStyle(Theme.slate500)
            }
        }
        .tint(Theme.accentDeep)
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private var unavailableCard: some View {
        Text("Номер появится, когда у контакта будет сохранён ключ.")
            .font(.system(size: 13)).foregroundStyle(Theme.slate500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Зачем это нужно")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.slate700)
            Text("Шифрование защищает переписку с тем, чей ключ у тебя сохранён. Совпадение номера подтверждает, что этот ключ принадлежит именно твоему собеседнику, а не тому, кто занял похожий ник. Сравни номер лично или голосом — не через переписку, которую проверяешь.")
                .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                .fixedSize(horizontal: false, vertical: true)
            Text("Если номер изменился, значит у контакта новое устройство или ключ подменили. Спроси его напрямую.")
                .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Scanner

    #if os(iOS)
    private var scannerSheet: some View {
        QRScannerView { payload in
            showScanner = false
            guard let scanned = SafetyNumber.digits(fromQR: payload), let mine = number else {
                scanResult = .mismatch
                return
            }
            scanResult = (scanned == mine) ? .match : .mismatch
        }
    }
    #endif
}
