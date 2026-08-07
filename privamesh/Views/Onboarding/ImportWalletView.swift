//
//  ImportWalletView.swift
//  privamesh
//

import SwiftUI
import SolanaSwift
#if os(iOS)
import UIKit
#endif

struct ImportWalletView: View {
    @Environment(AppRouter.self) private var router
    @Environment(WalletManager.self) private var wallet
    @Environment(\.modelContext) private var context

    @State private var words: [String] = Array(repeating: "", count: 12)
    @FocusState private var focusedField: Int?
    @State private var errorMessage: String?
    @State private var isImporting = false

    private var suggestions: [String] {
        guard let idx = focusedField else { return [] }
        let prefix = words[idx].lowercased().trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return [] }
        return Wordlists.english
            .filter { $0.hasPrefix(prefix) }
            .prefix(3)
            .map { String($0) }
    }

    private var isReadyToImport: Bool {
        words.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Восстановить аккаунт")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)

                        Text("Введи свои 12 слов по порядку. Аккаунт будет восстановлен с тем же ником и историей.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.slate500)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity)

                        #if os(iOS)
                        Button {
                            pasteAll()
                        } label: {
                            Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accentDeep)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.glass)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        #endif

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(0..<12, id: \.self) { index in
                                wordField(index: index)
                            }
                        }
                        .padding(.horizontal, 16)

                        if let errorMessage {
                            Text(LocalizedStringKey(errorMessage))
                                .font(.footnote)
                                .foregroundStyle(Theme.negative)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 16)
                }

                VStack(spacing: 12) {
                    // Errors also live next to the button: the copy inside the
                    // scroll view can sit off-screen behind the keyboard, which made
                    // a rejected tap look like no reaction at all.
                    if let errorMessage {
                        Text(LocalizedStringKey(errorMessage))
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.negative)
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if isImporting { ProgressView().tint(.white) }
                            Text(LocalizedStringKey(isImporting ? "Восстановление..." : "Войти в аккаунт"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background((!isReadyToImport || isImporting)
                            ? AnyShapeStyle(Color(red: 0.75, green: 0.75, blue: 0.75))
                            : AnyShapeStyle(Theme.accentGradient))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // Never disabled on an incomplete form: a greyed-out button that
                    // silently swallows taps reads as a broken app (App Review 2.1(a)
                    // on iPad). Tapping now always answers — with the exact reason.
                    .disabled(isImporting)

                    Button {
                        router.go(to: .welcome)
                    } label: {
                        Text("Назад")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.glass)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { word in
                        Button {
                            applySuggestion(word)
                        } label: {
                            Text(word)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.accent.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button("Готово") {
                        focusedField = nil
                    }
                    .font(.subheadline)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func wordField(index: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1).")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.slate400)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 28, alignment: .trailing)

            wordTextField(index: index)
                .onSubmit {
                    if index < 11 {
                        focusedField = index + 1
                    } else {
                        focusedField = nil
                    }
                }
                .onChange(of: words[index]) { _, newValue in
                    // Typing or pasting several words into ANY field spreads them
                    // across the grid from here. The "paste from clipboard" button
                    // needs the system pasteboard permission, which a reviewer can
                    // dismiss; typing into the field always works, so this is the
                    // reliable path — and a space finishes a word, as in a wallet.
                    let parsed = Self.parsePhrase(newValue)
                    let endsWord = newValue.last.map { !$0.isLetter } ?? false

                    if parsed.count >= 2 {
                        for (offset, word) in parsed.enumerated() where index + offset < 12 {
                            words[index + offset] = word
                        }
                        let next = index + parsed.count
                        focusedField = next < 12 ? next : nil
                        errorMessage = nil
                        return
                    }
                    words[index] = parsed.first ?? ""
                    if endsWord, !words[index].isEmpty, index < 11 {
                        focusedField = index + 1
                    }
                }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    @ViewBuilder
    private func wordTextField(index: Int) -> some View {
        let field = TextField("слово", text: $words[index])
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .focused($focusedField, equals: index)
            .submitLabel(index == 11 ? .done : .next)

        #if os(iOS)
        field.textInputAutocapitalization(.never)
        #else
        field
        #endif
    }

    private func applySuggestion(_ word: String) {
        guard let idx = focusedField else { return }
        words[idx] = word
        if idx < 11 {
            focusedField = idx + 1
        } else {
            focusedField = nil
        }
    }

    /// One recovery word: letters only, lowercased. Strips numbering ("1."),
    /// commas and smart punctuation that a paste or a tablet keyboard adds.
    static func normalize(_ raw: String) -> String {
        String(raw.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) })
    }

    /// Split arbitrary pasted text into recovery words. Accepts any separator
    /// (spaces, newlines, commas) and numbered lists.
    static func parsePhrase(_ raw: String) -> [String] {
        raw.split(whereSeparator: { !$0.isLetter })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    #if os(iOS)
    private func pasteAll() {
        guard let raw = UIPasteboard.general.string, !raw.isEmpty else {
            errorMessage = String(localized: "Буфер пуст — введи слова вручную или вставь фразу в первое поле")
            return
        }
        let parts = Self.parsePhrase(raw)
        guard parts.count >= 12 else {
            errorMessage = String(localized: "В буфере не 12 слов (нашёл \(parts.count))")
            return
        }
        words = Array(parts.prefix(12))
        errorMessage = nil
        focusedField = nil
    }
    #endif

    private func submit() {
        let cleaned = words.map { Self.normalize($0) }
        let missing = cleaned.enumerated().filter { $0.element.isEmpty }.map { $0.offset + 1 }
        if !missing.isEmpty {
            focusedField = missing.first.map { $0 - 1 }
            errorMessage = String(localized: "Заполни все 12 слов. Пустые: \(missing.map(String.init).joined(separator: ", "))")
            return
        }
        let unknown = cleaned.filter { !Wordlists.english.contains($0) }
        if !unknown.isEmpty {
            errorMessage = String(localized: "Не из BIP-39: \(unknown.joined(separator: ", "))")
            return
        }

        isImporting = true
        errorMessage = nil
        Task {
            do {
                try await wallet.importWallet(phrase: cleaned)
                await MainActor.run {
                    // App Review demo: restoring the demo seed pre-populates
                    // sample contacts + chats so every feature is verifiable.
                    if DemoContent.isDemoPhrase(cleaned), case let .ready(pk) = wallet.state {
                        DemoContent.populate(ownerAddress: pk, context: context)
                    }
                    isImporting = false
                    router.go(to: .passcodeSetup)
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = String(localized: "Не удалось восстановить аккаунт: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    ImportWalletView()
        .environment(AppRouter())
        .environment(WalletManager())
}
