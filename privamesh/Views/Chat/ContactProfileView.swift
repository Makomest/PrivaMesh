//
//  ContactProfileView.swift
//  privamesh
//
//  A contact's public profile: avatar, name, description, their NFT inventory
//  (avatars + nicknames) and what they have listed for sale (price under the
//  item). Data is the snapshot they shared via their ContactCard — offline and
//  point-in-time (no backend), so it reflects when they were added.
//

import SwiftUI
import SwiftData

struct ContactProfileView: View {
    let contact: Contact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showEdit = false

    private var profile: ProfileSnapshot? { contact.profile }
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    @Environment(\.openURL) private var openURL

    /// Where user reports are delivered. Serverless: a pre-filled email.
    private static let reportEmail = "privamesh@proton.me"

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        myInfoCard
                        if !contact.isSelf { muteCard }
                        if !contact.isSelf { safetyCard }
                        disappearCard
                        if let p = profile {
                            if !p.avatars.isEmpty { inventorySection("NFT-аватары", avatars: p.avatars, profile: p) }
                            if !p.nicknames.isEmpty { nicknamesSection(p) }
                            if p.avatars.isEmpty && p.nicknames.isEmpty {
                                emptyNote("Инвентарь пуст")
                            }
                        } else {
                            emptyNote("Профиль не получен.\nЭтот контакт добавлен без карточки профиля — попроси новый QR.")
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Профиль")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.foregroundStyle(Theme.accentDeep)
                }
                if !contact.isSelf {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Изменить") { showEdit = true }.foregroundStyle(Theme.accentDeep)
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                ContactEditSheet(contact: contact)
            }
        }
    }

    // MARK: - My info (added date, label, note)

    private var myInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                Text("Добавлен \(contact.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 13)).foregroundStyle(Theme.slate600)
                Spacer()
            }
            row(icon: "person.text.rectangle", title: "Твоя подпись", value: contact.displayName)
            row(icon: "note.text", title: "Заметка",
                value: contact.myNote.isEmpty ? "—" : contact.myNote,
                placeholder: contact.myNote.isEmpty)

            Button { showEdit = true } label: {
                Label("Изменить подпись и заметку", systemImage: "pencil")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentDeep)
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private var muteCard: some View {
        Toggle(isOn: Binding(
            get: { contact.isMuted },
            set: { contact.isMuted = $0; try? context.save() }
        )) {
            HStack(spacing: 8) {
                Image(systemName: contact.isMuted ? "bell.slash.fill" : "bell.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.slate400).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Без уведомлений").font(.system(size: 14)).foregroundStyle(Theme.slate800)
                    Text(LocalizedStringKey(contact.isMuted ? "Уведомления заглушены" : "Уведомления включены"))
                        .font(.system(size: 11)).foregroundStyle(Theme.slate500)
                }
            }
        }
        .tint(Theme.accentDeep)
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Safety (block + report) — UGC moderation (App Store Guideline 1.2)

    private var safetyCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { contact.isBlocked },
                set: { contact.isBlocked = $0; try? context.save() }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 13)).foregroundStyle(Theme.negative).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Заблокировать").font(.system(size: 14)).foregroundStyle(Theme.slate800)
                        Text(LocalizedStringKey(contact.isBlocked ? "Сообщения скрыты, новые не приходят" : "Перестать получать сообщения от контакта"))
                            .font(.system(size: 11)).foregroundStyle(Theme.slate500)
                    }
                }
            }
            .tint(Theme.negative)
            .padding(16)

            Divider().padding(.leading, 50).background(Theme.glassStroke)

            Button { report() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 13)).foregroundStyle(Theme.negative).frame(width: 18)
                    Text("Пожаловаться").font(.system(size: 14)).foregroundStyle(Theme.negative)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.slate400)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    /// Block the contact and open a pre-filled report email (no backend needed).
    private func report() {
        contact.isBlocked = true
        try? context.save()
        let subject = "PrivaMesh report: \(contact.id)"
        let body = "Reported user address: \(contact.id)\nReason: \n\n(describe the abusive content/behaviour)"
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        if let url = URL(string: "mailto:\(Self.reportEmail)?subject=\(enc(subject))&body=\(enc(body))") {
            openURL(url)
        }
    }

    private var disappearCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").font(.system(size: 13)).foregroundStyle(Theme.slate400).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Исчезающие сообщения").font(.system(size: 14)).foregroundStyle(Theme.slate800)
                Text(contact.disappearSeconds == 0
                     ? "Хранятся на устройстве"
                     : "Удаляются локально через \(DisappearingMessages.label(for: contact.disappearSeconds))")
                    .font(.system(size: 11)).foregroundStyle(Theme.slate500)
            }
            Spacer()
            Menu {
                ForEach(DisappearingMessages.options, id: \.seconds) { opt in
                    Button {
                        contact.disappearSeconds = opt.seconds
                        try? context.save()
                        DisappearingMessages.purge(contact, context: context)
                    } label: {
                        if contact.disappearSeconds == opt.seconds {
                            Label(LocalizedStringKey(opt.label), systemImage: "checkmark")
                        } else {
                            Text(LocalizedStringKey(opt.label))
                        }
                    }
                }
            } label: {
                Text(DisappearingMessages.label(for: contact.disappearSeconds))
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentDeep)
            }
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func row(icon: String, title: String, value: String, placeholder: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.slate400).frame(width: 18)
            Text(LocalizedStringKey(title)).font(.system(size: 13)).foregroundStyle(Theme.slate500)
            Spacer()
            Text(value).font(.system(size: 14))
                .foregroundStyle(placeholder ? Theme.slate400 : Theme.slate800)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Group {
                if let seed = profile?.activeAvatarSeed {
                    NFTAvatarView(seed: seed, size: 84)
                } else {
                    MeshAvatarView(id: contact.id, size: 84)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2)).clipShape(Circle())
                }
            }
            Text(contact.primaryName)
                .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
            if let saved = contact.secondaryName {
                Text("в контактах: \(saved)")
                    .font(.system(size: 12)).foregroundStyle(Theme.slate500)
            }
            Text(shortAddress(contact.id))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.slate400)
            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio).font(.system(size: 14)).foregroundStyle(Theme.slate600)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Sections

    private func inventorySection(_ title: String, avatars: [ProfileSnapshot.SnapAvatar], profile: ProfileSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(avatars, id: \.seed) { a in
                    itemTile(art: AnyView(NFTAvatarView(seed: a.seed, size: 80)),
                             name: a.name, price: profile.price(forRef: a.seed))
                }
            }
        }
    }

    private func nicknamesSection(_ profile: ProfileSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Ники")
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(profile.nicknames, id: \.self) { handle in
                    itemTile(art: AnyView(
                        ZStack {
                            Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text("@").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        }.frame(width: 80, height: 80)),
                        name: handle, price: profile.price(forRef: handle))
                }
            }
        }
    }

    private func itemTile(art: AnyView, name: String, price: Double?) -> some View {
        VStack(spacing: 8) {
            art
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.slate700).lineLimit(1)
            if let price {
                Text("\(price == price.rounded() ? "\(Int(price))" : String(format: "%.2g", price)) SOL")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.accentGradient).clipShape(Capsule())
            } else {
                Text("не продаётся").font(.system(size: 10)).foregroundStyle(Theme.slate400)
            }
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func sectionTitle(_ t: String) -> some View {
        HStack { Text(LocalizedStringKey(t)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.slate700); Spacer() }
    }

    private func emptyNote(_ t: String) -> some View {
        Text(LocalizedStringKey(t)).font(.system(size: 13)).foregroundStyle(Theme.slate500)
            .multilineTextAlignment(.center).padding(.top, 30)
    }

    private func shortAddress(_ s: String) -> String {
        guard s.count > 12 else { return s }
        return s.prefix(6) + "…" + s.suffix(6)
    }
}

// MARK: - Edit contact (label + note)

private struct ContactEditSheet: View {
    let contact: Contact
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Твоя подпись")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                        TextField("Как назвать контакт", text: $label)
                            .font(.system(size: 16))
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                            .padding(12)
                            .background(Theme.glass)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Заметка")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                        TextField("Короткая заметка о контакте…", text: $note, axis: .vertical)
                            .font(.system(size: 15)).lineLimit(2...5)
                            .padding(12)
                            .background(Theme.glass)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    Text("\(note.count)/140").font(.system(size: 11)).foregroundStyle(Theme.slate400)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Button {
                        let trimmed = label.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { contact.displayName = trimmed }
                        contact.myNote = String(note.prefix(140))
                        try? context.save()
                        dismiss()
                    } label: {
                        Text("Сохранить").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accentGradient).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Контакт")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
            .onAppear { label = contact.displayName; note = contact.myNote }
            .onChange(of: note) { _, v in if v.count > 140 { note = String(v.prefix(140)) } }
        }
    }
}
