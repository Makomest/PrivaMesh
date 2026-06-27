//
//  SecuritySetupView.swift
//  privamesh
//
//  One-time privacy-hardening offer shown to a new user after onboarding.
//  Explains each protection and lets them enable it right away.
//

import SwiftUI

struct SecuritySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoverTrafficService.self) private var coverTraffic
    @Environment(WalletManager.self) private var wallet
    @Environment(AccountManager.self) private var accountManager
    @Environment(GasWalletService.self) private var gasWallet
    @Environment(MessageSender.self) private var messageSender
    @Environment(MessagingIdentityManager.self) private var messagingIdentity
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(\.modelContext) private var context

    @State private var seedLockOn = SeedLock.isEnabled
    @State private var coverOn = false

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header

                        if SeedLock.isAvailable {
                            toggleCard(
                                icon: "faceid", color: Theme.accent,
                                title: "Защита seed по Face ID",
                                desc: "Чтение seed-фразы и подпись требуют Face ID / пароль. Если телефон попал в чужие руки — ключи не достать.",
                                isOn: $seedLockOn)
                        }

                        toggleCard(
                            icon: "theatermasks.fill", color: Color(red: 245/255, green: 158/255, blue: 11/255),
                            title: "Маскирующий трафик",
                            desc: "Периодически шлёт ложные (decoy) сообщения, чтобы скрыть, КОГДА ты реально пишешь. Стоит небольших сетевых комиссий.",
                            isOn: $coverOn)

                        linkCard(
                            icon: "fuelpump.fill", color: Color(red: 99/255, green: 102/255, blue: 241/255),
                            title: "Газ-кошелёк",
                            desc: "Отдельный кошелёк платит комиссии за сообщения, поэтому твой основной адрес НЕ появляется в блокчейне. Нужно создать и немного пополнить.") {
                                GasWalletView()
                            }

                        Text("Всё можно включить/выключить позже в Профиле → Приватность.")
                            .font(.system(size: 12)).foregroundStyle(Theme.slate400)
                            .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 4)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 100)
                }

                VStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Готово")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Theme.accentGradient).clipShape(Capsule())
                            .shadow(color: Theme.accent.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 28)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Пропустить") { dismiss() }.foregroundStyle(Theme.slate500)
                }
            }
            .onChange(of: seedLockOn) { _, v in
                SeedLock.isEnabled = v
                wallet.reapplySeedProtection()
                accountManager.reapplySeedProtection()
                SeedLock.invalidate()
            }
            .onChange(of: coverOn) { _, v in
                coverTraffic.isEnabled = v
                if v, case let .ready(address) = wallet.state {
                    coverTraffic.refresh(myAddress: address, wallet: wallet, gasWallet: gasWallet,
                                         identity: messagingIdentity, rpc: rpc,
                                         sender: messageSender, context: context)
                } else {
                    coverTraffic.stop()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 72, height: 72).blur(radius: 18).opacity(0.4)
                Image(systemName: "lock.shield.fill").font(.system(size: 40)).foregroundStyle(Theme.accentGradient)
            }
            .padding(.top, 12)
            Text("Усиль защиту")
                .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
            Text("PrivaMesh уже шифрует всё end-to-end. Включи доп. слои приватности — по желанию.")
                .font(.system(size: 14)).foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.center).padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    private func toggleCard(icon: String, color: Color, title: String, desc: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.slate800)
                Text(LocalizedStringKey(desc)).font(.system(size: 12)).foregroundStyle(Theme.slate500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(16).background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func linkCard<Destination: View>(icon: String, color: Color, title: String, desc: String,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.slate800)
                    Text(LocalizedStringKey(desc)).font(.system(size: 12)).foregroundStyle(Theme.slate500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.slate400)
            }
            .padding(16).background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
