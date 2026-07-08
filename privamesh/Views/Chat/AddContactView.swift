//
//  AddContactView.swift
//  privamesh
//
//  Two-tab contact addition:
//    • "Поиск" — search by nickname or Solana address via DiscoveryService
//    • "QR / Бандл" — classic QR scan or paste
//

import SwiftUI
import SwiftData
#if os(iOS)
import VisionKit
#endif

struct AddContactView: View {
    @Environment(MessagingIdentityManager.self) private var identity
    @Environment(WalletManager.self) private var wallet
    @Environment(DiscoveryService.self) private var discovery
    @Environment(OnChainDiscovery.self) private var onChainDiscovery
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(ToastManager.self) private var toast
    @Environment(AvatarService.self) private var avatars
    @Environment(MarketService.self) private var market
    @Environment(UserProfileService.self) private var userProfile
    @Environment(NicknameManager.self) private var nicknameManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Tab
    private enum Tab { case search, qr }
    @State private var activeTab: Tab = .search

    // Search tab state
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResult: DiscoveryService.DiscoveryUser?
    @State private var searchError: String?
    @State private var searchContactName = ""

    // QR tab state
    @State private var myBundleBase64 = ""
    @State private var cardCopied = false
    @State private var scannedBase64 = ""
    @State private var qrContactName = ""
    @State private var pasteText = ""
    @State private var showScanner = false

    // Shared
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()

                VStack(spacing: 0) {
                    tabPicker
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            if activeTab == .search {
                                searchContent
                            } else {
                                qrContent
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 80)
                    }
                }
            }
            .navigationTitle("Добавить контакт")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Theme.accentDeep)
                }
            }
            #endif
            .onAppear { loadOwnBundle() }
            .onChange(of: scannedBase64) { _, new in
                // Pre-fill the name field with the user's own NFT nick from the card.
                if qrContactName.isEmpty,
                   let nick = ContactCard.fromQRPayload(new)?.profile?.nickname, !nick.isEmpty {
                    qrContactName = nick
                }
            }
            .alert("Ошибка", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(LocalizedStringKey(msg)) }
            #if os(iOS)
            .sheet(isPresented: $showScanner) { scannerSheet }
            #endif
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabOption("Поиск по нику", tab: .search, icon: "magnifyingglass")
            tabOption("QR / Бандл", tab: .qr, icon: "qrcode")
        }
        .background(Theme.glassStroke)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func tabOption(_ label: String, tab: Tab, icon: String) -> some View {
        let isSelected = activeTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(LocalizedStringKey(label))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : Theme.slate600)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
            .clipShape(Capsule())
            .padding(3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search tab

    private var searchContent: some View {
        VStack(spacing: 16) {
            searchInputCard
            if let result = searchResult {
                searchResultCard(result)
            } else if let error = searchError {
                searchErrorView(error)
            } else {
                searchHint
            }
        }
    }

    private var searchInputCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accentDeep)
                Text("Найти пользователя")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.slate600)
                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "at")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.slate400)
                TextField("Ник или адрес Solana…", text: $searchQuery)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.slate800)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { performSearch() }
                if !searchQuery.isEmpty {
                    Button { searchQuery = ""; searchResult = nil; searchError = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.slate300)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(Theme.glassStroke, lineWidth: 1))

            Button { performSearch() } label: {
                HStack(spacing: 8) {
                    if isSearching { ProgressView().tint(.white).scaleEffect(0.85) }
                    Text(LocalizedStringKey(isSearching ? "Ищем…" : "Найти"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(searchQuery.isEmpty || isSearching
                    ? AnyShapeStyle(Color(white: 0.75))
                    : AnyShapeStyle(Theme.accentGradient))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(searchQuery.isEmpty || isSearching)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                Text("Чтобы тебя находили по нику — включи поиск в Профиле: «Сделать профиль доступным для поиска».")
                    .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func searchResultCard(_ result: DiscoveryService.DiscoveryUser) -> some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                Text("Пользователь найден")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.positive)
                Spacer()
            }

            HStack(spacing: 12) {
                MeshAvatarView(id: result.address, size: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.nickname)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.slate800)
                    Text(shortAddress(result.address))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.slate400)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Как сохранить в контактах")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.slate400)
                TextField("Имя контакта…", text: $searchContactName)
                    .font(.system(size: 15))
                    .padding(10)
                    .background(Theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.glassStroke, lineWidth: 1))
            }

            Button { addFromSearch(result) } label: {
                Label("Добавить контакт", systemImage: "person.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(searchContactName.isEmpty
                        ? AnyShapeStyle(Color(white: 0.75))
                        : AnyShapeStyle(Theme.accentGradient))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(searchContactName.isEmpty)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func searchErrorView(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.negative)
            Text(LocalizedStringKey(msg))
                .font(.system(size: 14))
                .foregroundStyle(Theme.negative)
            Spacer()
        }
        .padding(14)
        .background(Theme.negative.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
            .stroke(Theme.negative.opacity(0.20), lineWidth: 1))
    }

    private var searchHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.accentGradient)
            Text("Введи ник вида **SwiftFox#1234**\nили полный адрес Solana")
                .font(.system(size: 13))
                .foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    // MARK: - QR tab

    private var qrContent: some View {
        VStack(spacing: 16) {
            myQRCard
            scanCard
            if !scannedBase64.isEmpty { nameAndSaveCard }
        }
    }

    private var myQRCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "qrcode")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accentDeep)
                Text("Твоя карточка — поделись с контактом")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.slate600)
                Spacer()
            }
            if myBundleBase64.isEmpty {
                ProgressView().tint(Theme.accent).padding(40)
            } else {
                QRCodeView(text: myBundleBase64, size: 280)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = myBundleBase64
                    withAnimation { cardCopied = true }
                    Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { cardCopied = false } }
                    #endif
                } label: {
                    Label(cardCopied ? LocalizedStringKey("Скопировано") : LocalizedStringKey("Скопировать карточку"),
                          systemImage: cardCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(cardCopied ? Theme.positive : Theme.accentDeep)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    private var scanCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accentDeep)
                Text("Скан QR контакта")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.slate600)
                Spacer()
            }
            #if os(iOS)
            if DataScannerViewController.isSupported {
                Button { showScanner = true } label: {
                    Label("Открыть камеру", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
            }
            #endif
            HStack {
                Rectangle().fill(Theme.slate300.opacity(0.5)).frame(height: 1)
                Text("или вставь").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                Rectangle().fill(Theme.slate300.opacity(0.5)).frame(height: 1)
            }
            VStack(spacing: 8) {
                TextField("Вставь карточку контакта…", text: $pasteText, axis: .vertical)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3...5)
                    .padding(10)
                    .background(Theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                if !pasteText.isEmpty {
                    Button("Использовать этот бандл") {
                        scannedBase64 = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        pasteText = ""
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accentDeep)
                    .buttonStyle(.plain)
                }
            }
            if !scannedBase64.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                    Text("Карточка получена").font(.system(size: 13)).foregroundStyle(Theme.positive)
                }
            }
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    private var nameAndSaveCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accentDeep)
                Text("Имя контакта")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.slate600)
                Spacer()
            }
            TextField("Имя контакта…", text: $qrContactName)
                .font(.system(size: 15))
                .padding(10)
                .background(Theme.glass)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.glassStroke, lineWidth: 1))
            Button { addFromQR() } label: {
                Label("Добавить контакт", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(qrContactName.isEmpty
                        ? AnyShapeStyle(Color(white: 0.75))
                        : AnyShapeStyle(Theme.accentGradient))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(qrContactName.isEmpty)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    #if os(iOS)
    private var scannerSheet: some View {
        NavigationStack {
            QRScannerView { payload in
                scannedBase64 = payload
                showScanner = false
            }
            .ignoresSafeArea()
            .navigationTitle("Сканировать QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { showScanner = false }
                }
            }
        }
    }
    #endif

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.isEmpty, !isSearching else { return }
        isSearching = true
        searchResult = nil
        searchError = nil
        searchContactName = ""

        Task {
            // Serverless: scan the on-chain directory by nickname/address.
            let result = await onChainDiscovery.search(query: searchQuery, rpc: rpc)
            await MainActor.run {
                if let result {
                    searchResult = result
                    searchContactName = result.nickname
                } else {
                    searchError = "Никто с таким ником не найден. Возможно, он не включил поиск в Профиле («Сделать профиль доступным для поиска») — попроси его включить или добавь по QR."
                }
                isSearching = false
            }
        }
    }

    private func addFromSearch(_ result: DiscoveryService.DiscoveryUser) {
        do {
            let bundle = try PrekeyBundle.fromBase64(result.bundleBase64)
            try bundle.verify()
            // Search results come from an untrusted directory — REQUIRE a valid
            // wallet signature binding the bundle to the address, else it could
            // be an impersonation. (QR add is trusted in-person and is lenient.)
            guard bundle.isBoundTo(address: result.address) else {
                errorMessage = "Не удалось подтвердить подлинность контакта (нет валидной подписи аккаунта). Возможна подмена — добавь его по QR лично."
                showError = true
                return
            }
            let contact = Contact(
                id: result.address,
                displayName: searchContactName.trimmingCharacters(in: .whitespaces),
                prekeyBundleBase64: result.bundleBase64
            )
            contact.ownerAddress = myAddress ?? ""
            // Seed the contact's profile from the discovery record so their nick +
            // NFT avatar show immediately, before their first message arrives.
            var snap = ProfileSnapshot()
            snap.nickname = result.nickname
            snap.activeAvatarSeed = result.avatarSeed
            contact.profileData = try? JSONEncoder().encode(snap)
            context.insert(contact)
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func addFromQR() {
        guard !scannedBase64.isEmpty, !qrContactName.isEmpty else { return }
        do {
            // New format: a ContactCard carrying the Solana address + bundle.
            // Legacy bundle-only QRs have no address and can't receive on-chain
            // messages, so we reject them with a clear message.
            guard let card = ContactCard.fromQRPayload(scannedBase64) else {
                errorMessage = "Это старый QR без Solana-адреса. Попроси контакт показать новый QR (или добавь его через поиск)."
                showError = true
                return
            }
            guard card.hasValidAddress else {
                errorMessage = "В QR некорректный Solana-адрес получателя."
                showError = true
                return
            }
            let bundle = try PrekeyBundle.fromBase64(card.bundle)
            try bundle.verify()
            // If the QR carries a wallet signature it MUST match the address
            // (a tampered QR is rejected); legacy unsigned QRs are trusted
            // because they're exchanged in person.
            if bundle.walletAddress != nil, !bundle.isBoundTo(address: card.address) {
                errorMessage = "Подпись в QR не соответствует адресу — возможна подмена. Попроси новый QR."
                showError = true
                return
            }
            let contact = Contact(
                id: card.address,
                displayName: qrContactName,
                prekeyBundleBase64: card.bundle
            )
            if let p = card.profile { contact.profileData = try? JSONEncoder().encode(p) }
            contact.ownerAddress = myAddress ?? ""
            context.insert(contact)
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private var myAddress: String? {
        if case let .ready(addr) = wallet.state { return addr }
        if case let .draft(_, addr) = wallet.state { return addr }
        return nil
    }

    private func loadOwnBundle() {
        Task {
            guard let address = myAddress,
                  let bundle = try? identity.prekeyBundle() else {
                myBundleBase64 = ""
                return
            }
            // Bind the bundle to my wallet address so the scanner can verify it
            // wasn't swapped (anti-MITM). Falls back to unsigned if the key is
            // unavailable (older in-person trust still works).
            let signed = (try? await wallet.currentKeyPair())
                .map { bundle.walletSigned(address: address, keypair: $0) } ?? bundle
            let profile = userProfile.qrSnapshot(nickname: nicknameManager.nickname, avatars: avatars)
            myBundleBase64 = ContactCard(address: address, bundle: signed.base64Encoded,
                                         profile: profile).qrPayload
        }
    }

    // MARK: - Helpers

    private func shortAddress(_ addr: String) -> String {
        guard addr.count > 12 else { return addr }
        return addr.prefix(6) + "…" + addr.suffix(6)
    }
}
