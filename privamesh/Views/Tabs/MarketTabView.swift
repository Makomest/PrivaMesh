//
//  MarketTabView.swift
//  privamesh
//
//  Unified NFT marketplace: buy avatars & nicknames by category, list your own
//  items for sale, manage your listings & collection, and favourite lots.
//  Real SOL payments; listings discovered serverlessly via the on-chain registry
//  (see MarketRegistry). Ownership is still local (no Metaplex NFT yet).
//

import SwiftUI
import SolanaSwift

struct MarketTabView: View {
    @Environment(MarketService.self) private var market
    @Environment(MarketRegistry.self) private var registry
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(WalletManager.self) private var wallet
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(BiometryService.self) private var biometry
    @Environment(SOLPriceService.self) private var solPrice
    @Environment(ToastManager.self) private var toast

    private enum Section { case browse, sell, favorites }
    private enum PriceSort { case none, cheap, expensive }
    @State private var section: Section = .browse
    @State private var kind: MarketItem.Kind = .avatar
    @State private var showSellPicker = false
    @State private var priceTarget: MarketItem?
    @State private var buyTarget: MarketListing?

    @State private var searchText = ""
    @State private var sort: PriceSort = .none
    @State private var maxPriceText = ""
    @State private var selectedCollection: String?

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 0) {
                    header
                    sectionPicker.padding(.horizontal, 20).padding(.bottom, 10)
                    if section == .browse {
                        kindPicker.padding(.horizontal, 20).padding(.bottom, 8)
                            .onChange(of: kind) { selectedCollection = nil }
                    }
                    ScrollView {
                        switch section {
                        case .browse:    browseGrid
                        case .sell:      sellContent
                        case .favorites: favoritesContent
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .sheet(isPresented: $showSellPicker) { sellPickerSheet }
            .sheet(item: $priceTarget) { item in PriceSheet(item: item) }
            .sheet(item: $buyTarget) { lot in BuyConfirmSheet(listing: lot) }
            .task {
                await solPrice.refresh()
                await registry.refresh(rpc: rpc, market: market)
            }
            .refreshable { await registry.refresh(rpc: rpc, market: market) }
        }
    }

    // MARK: - Header / pickers

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Маркет")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.slate800)
                Text("NFT-аватары и ники")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentDeep)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            segButton("Маркет", .browse)
            segButton("Продать", .sell)
            segButton("Избранные", .favorites)
        }
        .background(Theme.glassStroke)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func segButton(_ label: String, _ value: Section) -> some View {
        let on = section == value
        return Button { withAnimation(.easeInOut(duration: 0.2)) { section = value } } label: {
            Text(LocalizedStringKey(label))
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? .white : Theme.slate600)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                .clipShape(Capsule()).padding(3)
        }
        .buttonStyle(.plain)
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            kindChip("Аватары", .avatar, icon: "person.crop.circle")
            kindChip("Ники", .nickname, icon: "at")
            Spacer()
        }
    }

    private func kindChip(_ label: String, _ value: MarketItem.Kind, icon: String) -> some View {
        let on = kind == value
        return Button { withAnimation(.easeInOut(duration: 0.2)) { kind = value } } label: {
            Label(LocalizedStringKey(label), systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? .white : Theme.slate600)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.glass))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Browse

    @ViewBuilder
    private var browseGrid: some View {
        VStack(spacing: 10) {
            searchAndFilter.padding(.horizontal, 16)

            if kind == .avatar && selectedCollection == nil {
                collectionsGrid
            } else {
                lotsList
            }

            Text("Покупка — реальный перевод SOL. Genesis-доход идёт разработчику, перепродажа — продавцу (комиссия \(Int(MarketService.resaleCommissionPercent))%).")
                .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.vertical, 16)
        }
        .padding(.bottom, 90)
    }

    private var searchAndFilter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.slate400)
                TextField(kind == .nickname ? LocalizedStringKey("Поиск ника (напр. neo)") : LocalizedStringKey("Поиск по названию"),
                          text: $searchText)
                    .font(.system(size: 14))
                    #if os(iOS)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    #endif
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.slate300) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.glass).clipShape(Capsule())

            HStack(spacing: 8) {
                Menu {
                    Button("Без сортировки") { sort = .none }
                    Button("Сначала дешёвые") { sort = .cheap }
                    Button("Сначала дорогие") { sort = .expensive }
                } label: {
                    Label(sortLabel, systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.slate600)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.glass).clipShape(Capsule())
                }
                HStack(spacing: 4) {
                    Text("до").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                    TextField("∞", text: $maxPriceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .font(.system(size: 12, weight: .medium)).frame(width: 44)
                    Text("SOL").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.glass).clipShape(Capsule())
                Spacer()
            }
        }
    }

    private var sortLabel: String {
        switch sort {
        case .none: return String(localized: "Сортировка")
        case .cheap: return String(localized: "Дешёвые")
        case .expensive: return String(localized: "Дорогие")
        }
    }

    private func applyFilters(_ lots: [MarketListing]) -> [MarketListing] {
        var r = lots
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { r = r.filter { $0.item.name.localizedCaseInsensitiveContains(q) } }
        if let maxP = Double(maxPriceText.replacingOccurrences(of: ",", with: ".")), maxP > 0 {
            r = r.filter { $0.priceSOL <= maxP }
        }
        switch sort {
        case .cheap:     r.sort { $0.priceSOL < $1.priceSOL }
        case .expensive: r.sort { $0.priceSOL > $1.priceSOL }
        case .none:      break
        }
        return r
    }

    private var collectionsGrid: some View {
        let collections = market.avatarCollections
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(collections, id: \.name) { col in
                Button { selectedCollection = col.name } label: {
                    VStack(spacing: 8) {
                        if let cover = market.listings(kind: .avatar)
                            .first(where: { ($0.item.collection ?? "Genesis") == col.name }) {
                            NFTAvatarView(seed: cover.item.ref, size: 88)
                        } else {
                            Circle().fill(Theme.accent.opacity(0.15)).frame(width: 88, height: 88)
                        }
                        Text(col.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.slate800)
                        Text("\(col.count) NFT").font(.system(size: 11)).foregroundStyle(Theme.slate500)
                    }
                    .padding(14).frame(maxWidth: .infinity)
                    .background(Theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var lotsList: some View {
        // Genesis (local primary) + live resale lots discovered on-chain via the
        // registry. De-dup by item id so a genesis design and its resale don't double.
        var base = market.listings(kind: kind)
        let liveLots = registry.listings.filter { $0.item.kind == kind }
        let known = Set(base.map(\.item.id))
        base += liveLots.filter { !known.contains($0.item.id) }
        if kind == .avatar, let c = selectedCollection {
            base = base.filter { ($0.item.collection ?? "Genesis") == c }
        }
        // 1-of-1: never show a lot the user already owns (genesis OR resale from
        // the registry). Once bought it disappears; a fully bought-out collection
        // empties out. Keep my own active listings (sellerIsMe) so I can delist.
        base = base.filter { $0.sellerIsMe || !market.owns($0.item) }
        let lots = applyFilters(base)
        return VStack(spacing: 10) {
            if kind == .avatar, let c = selectedCollection {
                HStack {
                    Button { selectedCollection = nil } label: {
                        Label("Коллекции", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentDeep)
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(c).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.slate600)
                }
                .padding(.horizontal, 18)
            }
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(lots) { lot in lotCard(lot, action: .buy) }
            }
            .padding(.horizontal, 16)
            if lots.isEmpty {
                Text("Ничего не найдено").font(.system(size: 13)).foregroundStyle(Theme.slate500).padding(.top, 30)
            }
        }
    }

    // MARK: - Sell

    private var sellContent: some View {
        VStack(spacing: 14) {
            Button { showSellPicker = true } label: {
                Label("Выставить предмет на продажу", systemImage: "tag")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Theme.accentGradient).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 4)

            let mine = market.myListings
            HStack {
                Text("Мои лоты на продаже")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.slate700)
                Spacer()
            }
            .padding(.horizontal, 18)

            if mine.isEmpty {
                Text("Пока ничего не продаёшь").font(.system(size: 13))
                    .foregroundStyle(Theme.slate400).padding(.top, 6)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(mine) { lot in lotCard(lot, action: .delist) }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 90)
    }

    private var sellPickerSheet: some View {
        let sellable = market.myCollection.filter { !market.isListed($0.id) && !market.isReserved($0) }
        return NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    if sellable.isEmpty {
                        Text("Нет предметов для продажи.\nКупи что-нибудь в маркете.")
                            .font(.system(size: 14)).foregroundStyle(Theme.slate500)
                            .multilineTextAlignment(.center).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(sellable) { item in
                                Button {
                                    showSellPicker = false
                                    priceTarget = item
                                } label: { itemCard(item) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Выбери предмет")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Закрыть") { showSellPicker = false }.foregroundStyle(Theme.accentDeep) } }
        }
    }

    // MARK: - Favorites

    private var favoritesContent: some View {
        // Drop favorites the user already bought — a 1-of-1 lot is gone once owned.
        let favs = market.favoriteListings.filter { !market.owns($0.item) }
        return VStack(spacing: 12) {
            if favs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "heart").font(.system(size: 34)).foregroundStyle(Theme.slate300)
                    Text("Нет избранного").font(.system(size: 14)).foregroundStyle(Theme.slate500)
                    Text("Жми ♥ на лотах в маркете").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                }.padding(.top, 50)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(favs) { lot in lotCard(lot, action: .buy) }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 90)
        .onAppear { market.pruneFavorites() }   // forget sold/owned favourites
    }

    // MARK: - Cards

    private enum CardAction { case buy, delist }

    private func lotCard(_ lot: MarketListing, action: CardAction) -> some View {
        VStack(spacing: 8) {
            ItemArt(item: lot.item, size: 92)
            Text(lot.item.name).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.slate700).lineLimit(1)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(priceLabel(lot.priceSOL)).font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accentDeep)
                    if let usd = solPrice.usdValue(sol: Decimal(lot.priceSOL)) {
                        Text(usdLabel(usd)).font(.system(size: 10))
                            .foregroundStyle(Theme.slate400)
                    }
                }
                Spacer()
                Button { market.toggleFavorite(lot) } label: {
                    Image(systemName: market.isFavorite(lot) ? "heart.fill" : "heart")
                        .foregroundStyle(market.isFavorite(lot) ? Theme.negative : Theme.slate400)
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            switch action {
            case .buy:
                if lot.sellerIsMe {
                    Text("Ваш лот").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.slate500).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Theme.slate400.opacity(0.12)).clipShape(Capsule())
                } else {
                    Button { buyTarget = lot } label: {
                        Text("Купить").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Theme.accentGradient).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            case .delist:
                Button {
                    market.delist(itemID: lot.item.id)
                    toast.show("Снято с продажи")
                    Task {
                        if MarketRegistry.isConfigured, let kp = try? await wallet.currentKeyPair() {
                            try? await registry.publishUnlist(itemId: lot.item.id, seller: market.myAddress,
                                                              keypair: kp, rpc: rpc)
                            await registry.refresh(rpc: rpc, market: market)
                        }
                    }
                } label: {
                    Text("Снять с продажи").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.negative).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Theme.negative.opacity(0.1)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func itemCard(_ item: MarketItem) -> some View {
        VStack(spacing: 8) {
            ItemArt(item: item, size: 80)
            Text(item.name).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.slate700).lineLimit(1)
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func priceLabel(_ p: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 9
        f.usesGroupingSeparator = false
        return (f.string(from: NSNumber(value: p)) ?? "\(p)") + " SOL"
    }

    private func usdLabel(_ usd: Double) -> String {
        if usd > 0 && usd < 0.01 { return "< $0.01" }
        return String(format: "≈ $%.2f", usd)
    }
}

// MARK: - Item art (avatar render or nickname tile)

private struct ItemArt: View {
    let item: MarketItem
    var size: CGFloat

    var body: some View {
        switch item.kind {
        case .avatar:
            NFTAvatarView(seed: item.ref, size: size)
        case .nickname:
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("@").font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Mint nickname sheet (premium)

struct MintNicknameSheet: View {
    @Environment(MarketService.self) private var market
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(WalletManager.self) private var wallet
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(BiometryService.self) private var biometry
    @Environment(SOLPriceService.self) private var price
    @Environment(ToastManager.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var minting = false
    @State private var feeLamports: UInt64?

    private var trimmed: String { handle.trimmingCharacters(in: .whitespaces) }
    private var available: Bool { market.isNicknameAvailable(trimmed) }
    private var canMint: Bool {
        available && market.canMint(isPremium: subscription.isSubscribed) && !minting
    }

    private var feeSOL: Double? { feeLamports.map { Double($0) / 1_000_000_000 } }
    private var feeUSD: Double? {
        guard let sol = feeSOL, let p = price.priceUSD else { return nil }
        return sol * p
    }
    private var feeText: String {
        guard let sol = feeSOL else { return "вычисляю…" }
        let usd = feeUSD.map { String(format: " ≈ $%.4f", $0) } ?? ""
        return String(format: "%.6f SOL%@", sol, usd)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 18) {
                    Image(systemName: "sparkles").font(.system(size: 40))
                        .foregroundStyle(Theme.accentGradient).padding(.top, 24)
                    Text("Создать NFT-ник")
                        .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
                    Text("Минт создаёт NFT в сети Solana — оплачивается сетевая комиссия. Ник станет твоим и его можно продать.\nЗаминчено: \(market.mintedNicknames.count)/\(MarketService.maxMintsPremium)")
                        .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)

                    HStack {
                        Text("@").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.slate400)
                        TextField("Твой ник", text: $handle)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Theme.glass).clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, 24)

                    if !trimmed.isEmpty {
                        Label(available ? "@\(trimmed) свободен" : "@\(trimmed) уже занят",
                              systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(available ? Theme.positive : Theme.negative)
                    }

                    // Real network fee for the mint tx.
                    HStack(spacing: 6) {
                        Image(systemName: "fuelpump.fill").font(.system(size: 11)).foregroundStyle(Theme.slate400)
                        Text("Комиссия сети: \(feeText)")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate600)
                    }

                    if canMint {
                        SlideToConfirm(text: minting ? "Минт…" : "Сдвинь, чтобы заминтить") {
                            Task { await mint() }
                        }
                        .padding(.horizontal, 24).padding(.top, 4)
                    } else {
                        Text(LocalizedStringKey(available ? "" : "Ник недоступен"))
                            .font(.system(size: 13)).foregroundStyle(Theme.slate400)
                            .frame(height: 54)
                    }
                    Spacer()
                }
            }
            .navigationTitle("NFT-ник")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
            .task(id: trimmed) { await refreshFee() }
            .task { await price.refresh() }
        }
    }

    private func refreshFee() async {
        guard trimmed.count >= 2, let keypair = try? await wallet.currentKeyPair() else { return }
        feeLamports = await MemoTransactionBuilder.estimateMintFee(
            from: keypair, handle: trimmed, endpointURL: rpc.currentEndpoint.address)
    }

    private func mint() async {
        // Premium-gated feature — guard the action itself, not just the button.
        guard market.canMint(isPremium: subscription.isSubscribed) else {
            toast.show(String(localized: "Минт NFT-ников — функция PrivaMesh+")); return
        }
        guard await biometry.confirm(reason: String(localized: "Подтвердить минт ника @\(trimmed)")) else { return }
        guard let keypair = try? await wallet.currentKeyPair() else { return }
        minting = true
        defer { minting = false }
        do {
            // Mint a real on-chain SPL NFT (supply 1) — ownership is seed-portable.
            _ = try await OnChainNFT.mint(designId: "nick:\(trimmed)", keypair: keypair, rpc: rpc)
            market.mintNickname(trimmed)
            toast.show(String(localized: "Ник заминчен: \(trimmed)"))
            dismiss()
        } catch {
            toast.show(String(localized: "Ошибка минта: \(error.localizedDescription)"))
        }
    }
}

// MARK: - Buy confirm sheet (slide to buy)

private struct BuyConfirmSheet: View {
    let listing: MarketListing
    @Environment(MarketService.self) private var market
    @Environment(BiometryService.self) private var biometry
    @Environment(SOLPriceService.self) private var price
    @Environment(ToastManager.self) private var toast
    @Environment(WalletManager.self) private var wallet
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(WalletBalanceService.self) private var balance
    @Environment(MarketRegistry.self) private var registry
    @Environment(\.dismiss) private var dismiss

    @State private var sendSOLService = SendSOLService()
    @State private var buying = false
    @State private var errorText: String?

    private var usd: Double? { price.usdValue(sol: Decimal(listing.priceSOL)) }

    static func priceText(_ p: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 9
        f.usesGroupingSeparator = false
        return (f.string(from: NSNumber(value: p)) ?? "\(p)") + " SOL"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 16) {
                    ItemArt(item: listing.item, size: 110).padding(.top, 24)
                    Text(listing.item.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
                    VStack(spacing: 2) {
                        Text(Self.priceText(listing.priceSOL))
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accentDeep)
                        if let usd { Text(String(format: "≈ $%.2f", usd))
                            .font(.system(size: 13)).foregroundStyle(Theme.slate500) }
                    }
                    Text("Реальная оплата SOL с твоего кошелька.")
                        .font(.system(size: 11)).foregroundStyle(Theme.slate400)

                    SlideToConfirm(text: buying ? "Покупаем…" : "Сдвинь, чтобы купить") {
                        Task { await purchase() }
                    }
                    .padding(.horizontal, 24).padding(.top, 6)
                    .disabled(buying)

                    if let errorText {
                        Text(LocalizedStringKey(errorText))
                            .font(.system(size: 12)).foregroundStyle(Theme.negative)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24).padding(.top, 8)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Покупка")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
            .task {
                await price.refresh()
                if case let .ready(addr) = wallet.state { await balance.refresh(publicKey: addr, rpc: rpc) }
            }
        }
    }

    /// Real purchase: pay the price in SOL to the dev wallet (genesis primary
    /// sale), then grant ownership only after the transfer confirms.
    @MainActor
    private func purchase() async {
        errorText = nil
        guard market.purchasesEnabled else { errorText = String(localized: "Покупки временно недоступны"); return }
        // Reject an absurd/forged price BEFORE any Decimal/UInt64 math (those trap
        // on inf/NaN/overflow and crashed the app).
        guard listing.priceSOL.isFinite, listing.priceSOL >= 0, listing.priceSOL <= PriceSheet.maxPriceSOL else {
            errorText = String(localized: "Некорректная цена лота"); return
        }
        // Don't pay for your own lot or something you already own (buy() would
        // no-op and the SOL would be gone for nothing).
        guard !listing.sellerIsMe else { errorText = String(localized: "Это твой лот"); return }
        guard !market.owns(listing.item) else { errorText = String(localized: "Уже у тебя в коллекции"); return }
        guard await biometry.confirm(reason: String(localized: "Подтвердить покупку: \(listing.item.name)")) else {
            errorText = String(localized: "Подтверждение не пройдено"); return
        }

        // Need price + fee AND must keep the wallet at/above Solana's rent-exempt
        // minimum (~0.00089 SOL) — a system account can't be left below it.
        let feeSOL = Double(SendSOLService.estimatedFeeLamports) / 1_000_000_000
        let rentReserve = 0.0009
        let needed = listing.priceSOL + feeSOL + rentReserve
        if let bal = balance.balanceSOL, bal < Decimal(needed) {
            errorText = String(localized: "Недостаточно SOL: нужно ≈ \(Self.priceText(needed)) (включая резерв ~0.0009 на rent), на балансе \(Self.priceText(NSDecimalNumber(decimal: bal).doubleValue))")
            return
        }
        guard let keypair = try? await wallet.currentKeyPair() else {
            errorText = String(localized: "Кошелёк недоступен"); return
        }

        buying = true
        defer { buying = false }

        do {
            if let seller = listing.sellerAddress, seller != MarketService.devWallet {
                // Live resale: pay seller (price − commission) + dev commission,
                // and close the lot with a `sold` memo — one atomic tx.
                let total = UInt64((listing.priceSOL * 1_000_000_000).rounded())
                let devCut = UInt64((Double(total) * MarketService.resaleCommissionPercent / 100).rounded())
                let sellerCut = total > devCut ? total - devCut : 0
                let buyerAddr = keypair.publicKey.base58EncodedString
                let sold = MarketEvent(type: .sold,
                                       lotId: MarketEvent.lotId(itemId: listing.item.id, seller: seller),
                                       seller: seller, buyer: buyerAddr)
                guard let memo = sold.memoString() else { throw NSError(domain: "market", code: 0) }
                _ = try await MemoTransactionBuilder.purchase(
                    from: keypair, seller: seller, sellerLamports: sellerCut,
                    dev: MarketService.devWallet, devLamports: devCut,
                    registry: MarketRegistry.address, memoBase64: memo,
                    endpointURL: rpc.currentEndpoint.address)
                market.buy(listing)
                toast.show(String(localized: "Куплено: \(listing.item.name)"))
                await registry.refresh(rpc: rpc, market: market)
                dismiss()
            } else {
                // Genesis primary sale: full price → dev wallet.
                await sendSOLService.send(from: keypair, to: MarketService.devWallet,
                                          amountSOL: Decimal(listing.priceSOL), rpc: rpc)
                switch sendSOLService.state {
                case .success:
                    market.buy(listing)
                    // Announce the genesis sale to the registry so this design
                    // leaves EVERYONE's market (true 1-of-1). Best-effort.
                    try? await registry.publishGenesisSold(
                        item: listing.item, buyer: keypair.publicKey.base58EncodedString,
                        keypair: keypair, rpc: rpc)
                    // Mint a real on-chain NFT to the buyer (seed-portable). Local
                    // ownership is already granted, so a mint failure doesn't lose
                    // the purchase — but surface it so it isn't silently local-only.
                    do {
                        _ = try await OnChainNFT.mint(designId: listing.item.id, keypair: keypair, rpc: rpc)
                        toast.show(String(localized: "Куплено: \(listing.item.name)"))
                    } catch {
                        toast.show(String(localized: "Куплено (локально). Ончейн-минт не удался: \(error.localizedDescription)"))
                    }
                    dismiss()
                case .failure(let msg):
                    errorText = msg
                default:
                    errorText = String(localized: "Транзакция не подтвердилась — попробуй ещё раз")
                }
            }
        } catch {
            errorText = String(localized: "Ошибка покупки: \(error.localizedDescription)")
        }
    }
}

// MARK: - Price sheet (set sale price)

private struct PriceSheet: View {
    let item: MarketItem
    @Environment(MarketService.self) private var market
    @Environment(MarketRegistry.self) private var registry
    @Environment(WalletManager.self) private var wallet
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(BiometryService.self) private var biometry
    @Environment(ToastManager.self) private var toast
    @Environment(SOLPriceService.self) private var solPrice
    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var listing = false

    private var price: Double? { Double(priceText.replacingOccurrences(of: ",", with: ".")) }

    /// Sanity cap. A huge/infinite price used to crash the app: Decimal(Double)
    /// traps on inf/NaN/overflow and the lamport math (price × 1e9) overflows UInt64.
    static let maxPriceSOL: Double = 1_000_000
    /// A usable listing price: positive, finite, within the cap.
    private var priceValid: Bool {
        guard let p = price else { return false }
        return p.isFinite && p > 0 && p <= Self.maxPriceSOL
    }
    private var priceTooBig: Bool {
        guard let p = price else { return false }
        return !p.isFinite || p > Self.maxPriceSOL
    }

    /// Trim trailing zeros (0.95, 1.9, 2) for the commission/net breakdown.
    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%g", v)
    }
    /// " · ≈ $X.XX" suffix, or empty when the price is unknown.
    static func usdSuffix(_ usd: Double?) -> String {
        guard let usd else { return "" }
        return usd < 0.01 ? " · ≈ <$0.01" : String(format: " · ≈ $%.2f", usd)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 20) {
                    ItemArt(item: item, size: 100).padding(.top, 28)
                    Text(item.name).font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                    if let paid = market.purchasePrice(item.id) {
                        Text("Куплено за \(paid == paid.rounded() ? "\(Int(paid))" : String(format: "%.2g", paid)) SOL")
                            .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                    }

                    HStack {
                        TextField("Цена", text: $priceText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .font(.system(size: 18, weight: .semibold))
                        Text("SOL").font(.system(size: 14)).foregroundStyle(Theme.slate500)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, 24)

                    if priceValid, let p = price {
                        let pct = MarketService.resaleCommissionPercent
                        let commission = p * pct / 100
                        let net = p - commission
                        let netUSD = solPrice.usdValue(sol: Decimal(net))
                        VStack(spacing: 6) {
                            HStack {
                                Text("Цена").font(.system(size: 13)).foregroundStyle(Theme.slate500)
                                Spacer()
                                Text("\(Self.fmt(p)) SOL\(Self.usdSuffix(solPrice.usdValue(sol: Decimal(p))))")
                                    .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                            }
                            HStack {
                                Text("Комиссия маркета \(Int(pct))%").font(.system(size: 13)).foregroundStyle(Theme.slate500)
                                Spacer()
                                Text("−\(Self.fmt(commission)) SOL").font(.system(size: 13)).foregroundStyle(Theme.slate500)
                            }
                            HStack {
                                Text("Ты получишь").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.slate800)
                                Spacer()
                                Text("\(Self.fmt(net)) SOL\(Self.usdSuffix(netUSD))")
                                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.positive)
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    if !subscription.isSubscribed {
                        Text("Бесплатно — до \(MarketService.freeListingLimit) лотов. PrivaMesh+ — без лимита.")
                            .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                    if priceValid {
                        SlideToConfirm(text: listing ? "Публикуем…" : "Сдвинь, чтобы выставить") {
                            guard priceValid, let p = price else { return }
                            guard market.canList(isPremium: subscription.isSubscribed) else {
                                toast.show(String(localized: "Лимит \(MarketService.freeListingLimit) лотов. Оформи PrivaMesh+ для безлимита."))
                                return
                            }
                            Task { await publishListing(price: p) }
                        }
                        .padding(.horizontal, 24)
                        .disabled(listing)
                    } else if priceTooBig {
                        Text("Слишком большая цена (макс 1 000 000 SOL)")
                            .font(.system(size: 13)).foregroundStyle(Theme.negative).frame(height: 54)
                    } else {
                        Text("Укажи цену").font(.system(size: 13)).foregroundStyle(Theme.slate400).frame(height: 54)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Цена продажи")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
        }
    }

    /// Record the lot locally and publish a `list` event to the on-chain registry
    /// so other users discover it. The publish fee is a tiny network fee.
    private func publishListing(price p: Double) async {
        guard await biometry.confirm(reason: "Выставить на продажу: \(item.name)") else { return }
        listing = true
        defer { listing = false }
        market.list(item: item, price: p)
        if MarketRegistry.isConfigured, let keypair = try? await wallet.currentKeyPair() {
            var listed = item
            listed.priceSOL = p
            do {
                try await registry.publishList(item: listed, seller: market.myAddress,
                                                keypair: keypair, rpc: rpc)
                await registry.refresh(rpc: rpc, market: market)
            } catch {
                toast.show(String(localized: "Лот сохранён, но публикация не удалась: \(error.localizedDescription)"))
                dismiss()
                return
            }
        }
        toast.show("Выставлено на продажу")
        dismiss()
    }
}
