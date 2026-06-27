//
//  EULAView.swift
//  privamesh
//
//  One-time Terms / acceptable-use agreement, required before using chat.
//  Apple Guideline 1.2 (user-generated content): a EULA with a zero-tolerance
//  policy for objectionable content + abusive users must be agreed to.
//

import SwiftUI

struct EULAView: View {
    /// Set true when the user accepts; persisted by the caller.
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 40)).foregroundStyle(Theme.accentGradient)
                        .padding(.top, 36)
                    Text("Условия использования")
                        .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        clause("Запрещённый контент",
                               "Действует политика НУЛЕВОЙ терпимости к оскорбительному, незаконному или абьюзивному контенту и поведению. Нарушители блокируются.")
                        clause("Жалобы и блокировка",
                               "Ты можешь пожаловаться на любого пользователя или сообщение и заблокировать собеседника в любой момент. Жалобы рассматриваются.")
                        clause("Сквозное шифрование",
                               "Сообщения зашифрованы end-to-end и хранятся на блокчейне. Разработчик НЕ имеет доступа к их содержимому и не может его удалить.")
                        clause("Самостоятельное хранение",
                               "Ты единолично контролируешь свой seed-ключ. Потеря ключа = потеря доступа. Разработчик не может восстановить аккаунт или средства.")
                        clause("Ответственность",
                               "Ты отвечаешь за свои сообщения и транзакции. Сетевые действия необратимы и стоят реальных комиссий.")
                    }
                    .padding(20)
                }

                VStack(spacing: 10) {
                    Button { onAccept() } label: {
                        Text("Принимаю")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Theme.accentGradient).clipShape(Capsule())
                            .shadow(color: Theme.accent.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                    Text("Нажимая «Принимаю», ты соглашаешься с условиями и политикой нулевой терпимости к абьюзу.")
                        .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24).padding(.bottom, 32)
            }
        }
    }

    private func clause(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.slate800)
            Text(LocalizedStringKey(body)).font(.system(size: 13)).foregroundStyle(Theme.slate600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
    }
}
