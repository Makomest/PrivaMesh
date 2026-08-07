//
//  OnboardingExplainerView.swift
//  privamesh
//
//  First-launch explainer: privacy, decentralization, cost. Monochrome, on the
//  same black mesh ground as the app itself — hierarchy through weight, size and
//  opacity, never colour.
//

import SwiftUI

struct OnboardingExplainerView: View {
    @Environment(AppRouter.self) private var router

    @State private var currentPage: Int = {
        #if DEBUG
        let a = CommandLine.arguments   // -onboardingPage N jumps straight to a slide for screenshots
        if let i = a.firstIndex(of: "-onboardingPage"), i + 1 < a.count, let p = Int(a[i + 1]) { return p }
        #endif
        return 0
    }()
    private let totalPages = 7

    var body: some View {
        ZStack {
            OrbitMeshBackground(intensity: 1.3)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button { finish() } label: {
                            Text("Пропустить")
                                .font(.system(size: 14))
                                .foregroundStyle(Orbit.label3)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8).padding(.trailing, 4)
                .frame(height: 44)

                TabView(selection: $currentPage) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        OnboardingPage(slide: slides[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                VStack(spacing: 28) {
                    dotsIndicator

                    Button {
                        if currentPage == totalPages - 1 { finish() }
                        else { withAnimation(.easeInOut(duration: 0.35)) { currentPage += 1 } }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentPage == totalPages - 1 ? "Начать общение" : "Далее")
                                .font(.system(size: 17, weight: .semibold))
                            if currentPage < totalPages - 1 {
                                Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .foregroundStyle(Orbit.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Orbit.label, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut, value: currentPage)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }

    private var dotsIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Orbit.label : Orbit.label.opacity(0.22))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "privamesh.onboardingDone")
        router.go(to: .welcome)
    }

    // MARK: - Slide data

    private var slides: [SlideData] {[
        SlideData(icon: "lock.shield.fill", badge: nil,
            title: "Приватность\nпо умолчанию",
            subtitle: "Каждое сообщение защищено военным уровнем шифрования — ещё до отправки.",
            points: [
                PointData(icon: "key.fill", text: "**Double Ratchet** — новый ключ для каждого сообщения"),
                PointData(icon: "eye.slash.fill", text: "**Одноразовые адреса** — новый адрес для каждого сообщения"),
                PointData(icon: "person.fill.questionmark", text: "**Без телефона и email** — только фраза восстановления = твоя личность"),
            ]),
        SlideData(icon: "eye.slash.circle.fill", badge: nil,
            title: "Слои\nанонимности",
            subtitle: "Скрыто не только содержимое — но и кто, с кем и когда переписывается.",
            points: [
                PointData(icon: "person.2.fill", text: "**Раздельные ключи аккаунтов** — твои аккаунты не связать между собой"),
                PointData(icon: "building.columns.fill", text: "**Комиссии платит приложение** — твой адрес не раскрывается"),
                PointData(icon: "theatermasks.fill", text: "**Маскирующий трафик** — ложные сообщения прячут, когда ты пишешь"),
            ]),
        SlideData(icon: "lock.iphone", badge: nil,
            title: "Защита\nна устройстве",
            subtitle: "Ключи и переписка защищены даже если телефон попал в чужие руки.",
            points: [
                PointData(icon: "faceid", text: "**Face ID на ключи** — в Keychain под биометрией"),
                PointData(icon: "timer", text: "**Исчезающие сообщения** — авто-удаление локальных копий"),
                PointData(icon: "checkmark.shield.fill", text: "**Подпись контактов** — защита от подмены собеседника (MITM)"),
            ]),
        SlideData(icon: "network", badge: nil,
            title: "Нет сервера\nсообщений",
            subtitle: "Твои чаты живут зашифрованными в блокчейне — не в нашей базе и не в облаке.",
            points: [
                PointData(icon: "lock.fill", text: "**Сквозное шифрование** — мы физически не можем прочитать переписку"),
                PointData(icon: "cube.fill", text: "**On-chain, не на наших серверах** — нет базы, которую взломать или запросить по суду"),
                PointData(icon: "eye.slash.fill", text: "**Комиссию платим вслепую** — relay не видит ни кто, ни что ты отправляешь"),
            ]),
        SlideData(icon: "paperplane.circle.fill", badge: "10 free",
            title: "Просто\nпиши",
            subtitle: "Комиссии сети мы оплачиваем за тебя. Никакой криптовалюты — только сообщения.",
            points: [
                PointData(icon: "gift.fill", text: "**10 бесплатных сообщений** каждый месяц — сразу, без оплаты"),
                PointData(icon: "star.circle.fill", text: "**PrivaMesh+** — от $5.99/мес: больше сообщений, галочка, 3 аккаунта"),
                PointData(icon: "bag.fill", text: "**Пакеты сообщений** — разовая покупка без подписки"),
            ]),
        SlideData(icon: "iphone.and.arrow.forward", badge: nil,
            title: "Переписка\nтолько у тебя",
            subtitle: "Расшифрованные сообщения хранятся только на этом телефоне — не в облаке и не на сервере.",
            points: [
                PointData(icon: "key.horizontal.fill", text: "**Личность** вернётся по 12 словам на любом устройстве"),
                PointData(icon: "iphone.slash", text: "**История чатов не переедет** на новый телефон — копии есть только здесь"),
                PointData(icon: "lock.shield.fill", text: "**Это защита, а не баг** — даже с твоей фразой восстановления никто не прочитает старую переписку"),
            ]),
        SlideData(icon: "checkmark.seal.fill", badge: nil,
            title: "Ты готов\nк старту",
            subtitle: "Создай аккаунт или восстанови существующий — займёт меньше минуты.",
            points: [
                PointData(icon: "person.badge.key.fill", text: "**Никакой регистрации** — фраза восстановления = твой аккаунт навсегда"),
                PointData(icon: "arrow.clockwise.circle.fill", text: "**Восстанавливается** на любом устройстве только по 12 словам"),
                PointData(icon: "at.circle.fill", text: "**Уникальный ник** генерируется автоматически из твоего ключа"),
            ]),
    ]}
}

// MARK: - Data models

private struct SlideData {
    let icon: String
    let badge: String?
    let title: String
    let subtitle: String
    let points: [PointData]
}

private struct PointData {
    let icon: String
    let text: String
}

// MARK: - Single slide view

private struct OnboardingPage: View {
    let slide: SlideData

    @State private var appear = false      // staggered content reveal
    @State private var pop = false         // icon spring-in
    @State private var pulse = false       // glow breathing
    @State private var spin = false        // orbiting ring

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                animatedIcon

                VStack(spacing: 12) {
                    Text(LocalizedStringKey(slide.title))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Orbit.label)
                        .multilineTextAlignment(.center)
                        .staggered(appear, index: 1)

                    Text(LocalizedStringKey(slide.subtitle))
                        .font(.system(size: 15))
                        .foregroundStyle(Orbit.label2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)
                        .staggered(appear, index: 2)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<slide.points.count, id: \.self) { i in
                        let point = slide.points[i]
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: point.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(Orbit.label)
                                .frame(width: 24)

                            Text(.init(point.text))
                                .font(.system(size: 14))
                                .foregroundStyle(Orbit.label2)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                        .staggered(appear, index: 3 + i)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .orbitGlassPanel(Theme.radiusMedium)
            }
            .padding(.horizontal, 28)
            .padding(.top, 64)
            .padding(.bottom, 20)
        }
        .onAppear { runEntrance() }
        .onDisappear { appear = false; pop = false; pulse = false; spin = false }
    }

    // MARK: Animated icon — monochrome: glass disc, white glyph, dashed white ring

    private var animatedIcon: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                // Soft white breathing bloom (glass needs light behind it).
                Circle()
                    .fill(Color.white)
                    .frame(width: 96, height: 96)
                    .blur(radius: 26)
                    .opacity(pulse ? 0.16 : 0.07)
                    .scaleEffect(pulse ? 1.08 : 0.92)

                // Orbiting hairline ring — a nod to the globe's horizon.
                Circle()
                    .stroke(Orbit.label.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 8]))
                    .frame(width: 112, height: 112)
                    .rotationEffect(.degrees(spin ? 360 : 0))

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(Orbit.label.opacity(0.18), lineWidth: 1))

                Image(systemName: slide.icon)
                    .resizable().scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundStyle(Orbit.label)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 120, height: 120)
            .scaleEffect(pop ? 1 : 0.5)
            .opacity(pop ? 1 : 0)
            .rotationEffect(.degrees(pop ? 0 : -25))

            if let badge = slide.badge {
                Text(badge)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Orbit.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Orbit.label, in: Capsule())
                    .scaleEffect(appear ? 1 : 0.4)
                    .opacity(appear ? 1 : 0)
            }
        }
    }

    private func runEntrance() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { pop = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { appear = true }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) { spin = true }
    }
}

// MARK: - Staggered reveal modifier

private extension View {
    func staggered(_ visible: Bool, index: Int) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 18)
            .animation(.spring(response: 0.5, dampingFraction: 0.75)
                .delay(0.12 + Double(index) * 0.07), value: visible)
    }
}

#Preview {
    OnboardingExplainerView()
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
