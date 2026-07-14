//
//  ChatsTabView.swift
//  privamesh
//
//  Contact list — matches ChatsScreen.tsx design.
//

import SwiftUI
import SwiftData

struct ChatsTabView: View {
    @Environment(PollingService.self) private var polling
    @Environment(WalletManager.self) private var wallet
    @Environment(MessageQuotaService.self) private var quota
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(AvatarService.self) private var avatars
    @Environment(NicknameManager.self) private var nicknameManager
    @Environment(\.modelContext) private var context

    @Query(sort: \Contact.createdAt, order: .reverse) private var allContacts: [Contact]

    private var activeAddress: String {
        if case let .ready(pk) = wallet.state { return pk }
        return ""
    }
    /// Only this account's chats.
    private var contacts: [Contact] {
        allContacts.filter { $0.ownerAddress == activeAddress || $0.ownerAddress.isEmpty }
    }

    @State private var showAddContact = false
    @State private var showProfile = false
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var contactToDelete: Contact?
    @State private var contactToClear: Contact?

    // Self-contact is always shown first; search filters by displayName.
    private var sorted: [Contact] {
        contacts.sorted {
            if $0.isSelf != $1.isSelf { return $0.isSelf }
            return $0.createdAt > $1.createdAt
        }
    }

    private var filtered: [Contact] {
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.primaryName.localizedCaseInsensitiveContains(searchText)
            || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()

                VStack(spacing: 0) {
                    header
                    quotaTile
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    let nonSelf = filtered.filter { !$0.isSelf }
                    if filtered.isEmpty || nonSelf.isEmpty && filtered.allSatisfy(\.isSelf) {
                        VStack(spacing: 0) {
                            if let self_ = filtered.first(where: \.isSelf) {
                                savedMessagesSection(self_)
                            }
                            emptyState
                        }
                    } else {
                        contactList
                    }
                }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .sheet(isPresented: $showAddContact) {
                AddContactView()
            }
            .sheet(isPresented: $showProfile) {
                ProfileTabView()
            }
            .sheet(isPresented: $showPaywall) {
                QuotaPaywallSheet()
            }
            .confirmationDialog("Удалить контакт?",
                                isPresented: Binding(get: { contactToDelete != nil },
                                                     set: { if !$0 { contactToDelete = nil } }),
                                presenting: contactToDelete) { c in
                Button("Удалить контакт и переписку", role: .destructive) { deleteContact(c) }
                Button("Отмена", role: .cancel) {}
            } message: { c in
                Text("«\(c.displayName)» и вся переписка с ним будут удалены с этого устройства. Контакт по-прежнему сможет тебе написать.")
            }
            .confirmationDialog("Очистить чат?",
                                isPresented: Binding(get: { contactToClear != nil },
                                                     set: { if !$0 { contactToClear = nil } }),
                                presenting: contactToClear) { c in
                Button("Очистить переписку", role: .destructive) { clearChat(c) }
                Button("Отмена", role: .cancel) {}
            } message: { c in
                Text("Все сообщения этого чата будут удалены с этого устройства. Сам контакт останется.")
            }
        }
    }

    // MARK: - Delete actions (local only)

    private func clearChat(_ contact: Contact) {
        for m in contact.messages { context.delete(m) }
        try? context.save()
    }

    private func deleteContact(_ contact: Contact) {
        // Cascade rule on Contact.messages removes the chat too.
        context.delete(contact)
        try? context.save()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            // Brand row + add.
            HStack {
                Text("PRIVAMESH")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Theme.slate400)
                Spacer()
                Button { showAddContact = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.accentGradient)
                        .clipShape(Circle())
                        .shadow(color: Theme.accent.opacity(0.45), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }

            // Identity row: avatar + our own nickname.
            HStack(spacing: 12) {
                Button { showProfile = true } label: {
                    Group {
                        if let seed = avatars.activeDesign?.id {
                            NFTAvatarView(seed: seed, size: 52)
                        } else {
                            MeshAvatarView(id: activeAddress.isEmpty ? "me" : activeAddress, size: 52)
                        }
                    }
                    .overlay(Circle().stroke(Theme.glassStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(nicknameManager.nickname)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                            .lineLimit(1)
                        if subscription.isSubscribed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 15)).foregroundStyle(Theme.accent)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.positive)
                        Text("Сквозное шифрование")
                            .font(.system(size: 11)).foregroundStyle(Theme.accentDeep)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Quota tile

    private var quotaTile: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.accentGradient).frame(width: 44, height: 44)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Осталось сообщений")
                        .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                    Text("\(quota.remaining)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text(subscription.isSubscribed ? "Ещё" : "Купить")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.accentGradient)
                    .clipShape(Capsule())
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusLarge))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Theme.slate400)
            TextField("Поиск чатов", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(Theme.slate800)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 80, height: 80)
                    .blur(radius: 16)
                    .opacity(0.35)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accentGradient)
            }
            Text("Пока нет контактов")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.slate800)
            Text("Добавь контакт по QR-коду,\nчтобы начать защищённую переписку.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showAddContact = true
            } label: {
                Label("Добавить контакт", systemImage: "person.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Theme.accentGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Saved Messages section (shown alone when no other contacts)

    private func savedMessagesSection(_ contact: Contact) -> some View {
        NavigationLink {
            ChatDetailView(contact: contact)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    LinearGradient(
                        colors: [Theme.accent, Theme.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Избранное")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.slate800)
                        Spacer()
                        if let last = contact.lastMessage {
                            Text(last.sentAt.formatted(.relative(presentation: .named)))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.slate400)
                        }
                    }
                    Text(contact.lastMessage.map { LocalizedStringKey($0.body) } ?? LocalizedStringKey("Личные заметки и медиа"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.slate500)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(contact) }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Row context menu

    @ViewBuilder
    private func rowMenu(_ contact: Contact) -> some View {
        Button {
            contactToClear = contact
        } label: {
            Label("Очистить чат", systemImage: "eraser")
        }
        if !contact.isSelf {
            Button {
                contact.isBlocked.toggle()
                try? context.save()
            } label: {
                Label(contact.isBlocked ? "Разблокировать" : "Заблокировать",
                      systemImage: contact.isBlocked ? "hand.raised.slash" : "hand.raised")
            }
            Button(role: .destructive) {
                contactToDelete = contact
            } label: {
                Label("Удалить контакт", systemImage: "trash")
            }
        }
    }

    // MARK: - Contact list

    private var contactList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filtered) { contact in
                    NavigationLink {
                        ChatDetailView(contact: contact)
                    } label: {
                        contactRow(contact)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { rowMenu(contact) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
    }

    private func contactRow(_ contact: Contact) -> some View {
        // Decode the JSON profile + scan messages once per render (these are
        // computed properties — avoid re-running them for every subview).
        let profile = contact.profile
        let last = contact.lastMessage
        return HStack(spacing: 12) {
            if contact.isSelf {
                ZStack {
                    LinearGradient(
                        colors: [Theme.accent, Theme.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
            } else if let seed = profile?.activeAvatarSeed {
                NFTAvatarView(seed: seed, size: 48)
            } else {
                MeshAvatarView(id: contact.id, size: 48)
            }

            let nick = (profile?.nickname).flatMap { $0.isEmpty ? nil : $0 }
            let primary = nick ?? contact.displayName
            let secondary = (nick != nil && nick != contact.displayName) ? contact.displayName : nil
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(contact.isSelf ? "Избранное" : primary))
                        .font(.system(size: 15, weight: contact.isSelf ? .medium : .regular))
                        .foregroundStyle(Theme.slate800)
                    if !contact.isSelf, profile?.isPremium == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    if let saved = secondary {
                        Text("· \(saved)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.slate400)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let last {
                        Text(last.sentAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.slate400)
                    }
                }
                HStack {
                    if let last {
                        Text(last.body)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.slate500)
                            .lineLimit(1)
                    } else {
                        Text(LocalizedStringKey(contact.isSelf ? "Личные заметки и медиа" : "Нет сообщений"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.slate400)
                    }
                    Spacer()
                    let unread = contact.unreadCount
                    if unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accentGradient)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
        .contentShape(Rectangle())
    }
}

#Preview {
    ChatsTabView()
        .environment(PollingService())
        .modelContainer(for: [Contact.self, ChatMessage.self], inMemory: true)
}
