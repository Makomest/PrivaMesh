//
//  AvatarStoreView.swift
//  privamesh
//
//  "My avatars": pick which owned NFT avatar is active. Buying and selling
//  live in the Market tab.
//

import SwiftUI

struct AvatarStoreView: View {
    @Environment(AvatarService.self) private var avatars
    @Environment(NicknameManager.self) private var nicknameManager
    @Environment(ToastManager.self) private var toast
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 0) {
                    activePreview
                    ScrollView { ownedGrid }
                        .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Мои аватары")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.foregroundStyle(Theme.accentDeep)
                }
            }
        }
    }

    private var activePreview: some View {
        VStack(spacing: 10) {
            Group {
                if let active = avatars.activeDesign {
                    NFTAvatarView(seed: active.id, size: 88)
                } else {
                    MeshAvatarView(id: nicknameManager.nickname, size: 88)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
                        .clipShape(Circle())
                }
            }
            Text(LocalizedStringKey(avatars.activeDesign?.name ?? "Базовый аватар"))
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.slate700)
            if avatars.activeDesign != nil {
                Button {
                    avatars.setActive(nil)
                    toast.show("Вернул базовый аватар")
                } label: {
                    Text("Снять NFT-аватар").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accentDeep)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12).padding(.bottom, 8)
    }

    private var ownedGrid: some View {
        VStack(spacing: 12) {
            if avatars.ownedDesigns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 34)).foregroundStyle(Theme.slate300)
                    Text("У тебя пока нет аватаров").font(.system(size: 14)).foregroundStyle(Theme.slate500)
                    Text("Купить можно в маркете — загрузить своё фото нельзя.")
                        .font(.system(size: 12)).foregroundStyle(Theme.slate400).multilineTextAlignment(.center)
                }
                .padding(.top, 50)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(avatars.ownedDesigns) { d in
                        let isActive = avatars.activeID == d.id
                        VStack(spacing: 8) {
                            NFTAvatarView(seed: d.id, size: 88)
                            Text(d.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.slate700)
                            Button {
                                avatars.setActive(isActive ? nil : d.id)
                                toast.show(isActive ? "Снято" : "Установлено")
                            } label: {
                                Text(LocalizedStringKey(isActive ? "Активен" : "Поставить"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isActive ? Theme.accentDeep : .white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(isActive
                                        ? AnyShapeStyle(Theme.accent.opacity(0.15))
                                        : AnyShapeStyle(Theme.accentGradient))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12).frame(maxWidth: .infinity)
                        .background(Theme.glass)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(isActive ? Theme.accent : Theme.glassStroke, lineWidth: isActive ? 2 : 1))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 40)
    }
}
