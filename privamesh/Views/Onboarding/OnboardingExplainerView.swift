//
//  OnboardingExplainerView.swift
//  privamesh
//
//  Interactive 4-slide onboarding explaining privacy, decentralization,
//  and blockchain cost. Shown only on first launch.
//

import SwiftUI

struct OnboardingExplainerView: View {
    @Environment(AppRouter.self) private var router

    @State private var currentPage = 0
    private let totalPages = 7

    var body: some View {
        ZStack {
            PastelBackground()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button {
                            finish()
                        } label: {
                            Text("Пропустить")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.slate400)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 4)
                .frame(height: 44)

                // Pages
                TabView(selection: $currentPage) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        OnboardingPage(slide: slides[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Dots + button
                VStack(spacing: 28) {
                    dotsIndicator

                    if currentPage == totalPages - 1 {
                        Button {
                            finish()
                        } label: {
                            Text("Начать общение")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.accentGradient)
                                .clipShape(Capsule())
                                .shadow(color: Theme.accent.opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                currentPage += 1
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Далее")
                                    .font(.system(size: 17, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accentGradient)
                            .clipShape(Capsule())
                            .shadow(color: Theme.accent.opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
                .animation(.easeInOut, value: currentPage)
            }
        }
    }

    private var dotsIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Theme.accent : Theme.slate300)
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
        SlideData(
            icon: "lock.shield.fill",
            iconColors: [Color(red: 52/255, green: 211/255, blue: 153/255),
                         Color(red: 20/255, green: 184/255, blue: 166/255)],
            badge: nil,
            title: "Приватность\nпо умолчанию",
            subtitle: "Каждое сообщение защищено военным уровнем шифрования — ещё до отправки.",
            points: [
                PointData(icon: "key.fill",
                          color: Color(red: 20/255, green: 184/255, blue: 166/255),
                          text: "**Double Ratchet** — новый ключ для каждого сообщения"),
                PointData(icon: "eye.slash.fill",
                          color: Color(red: 99/255, green: 102/255, blue: 241/255),
                          text: "**Stealth адреса** — одноразовый адрес на каждую транзакцию"),
                PointData(icon: "person.fill.questionmark",
                          color: Color(red: 245/255, green: 158/255, blue: 11/255),
                          text: "**Без телефона и email** — только seed phrase = твоя личность"),
            ]
        ),
        SlideData(
            icon: "eye.slash.circle.fill",
            iconColors: [Color(red: 99/255, green: 102/255, blue: 241/255),
                         Color(red: 56/255, green: 189/255, blue: 248/255)],
            badge: nil,
            title: "Слои\nанонимности",
            subtitle: "Скрыто не только содержимое — но и кто, с кем и когда переписывается.",
            points: [
                PointData(icon: "person.2.fill",
                          color: Color(red: 20/255, green: 184/255, blue: 166/255),
                          text: "**Раздельные ключи аккаунтов** — твои аккаунты не связать между собой"),
                PointData(icon: "building.columns.fill",
                          color: Color(red: 99/255, green: 102/255, blue: 241/255),
                          text: "**Комиссии платит приложение** — в блокчейне виден общий оплатитель, не твой адрес"),
                PointData(icon: "theatermasks.fill",
                          color: Color(red: 245/255, green: 158/255, blue: 11/255),
                          text: "**Маскирующий трафик** — ложные сообщения прячут, когда ты пишешь"),
            ]
        ),
        SlideData(
            icon: "lock.iphone",
            iconColors: [Color(red: 52/255, green: 211/255, blue: 153/255),
                         Color(red: 20/255, green: 184/255, blue: 166/255)],
            badge: nil,
            title: "Защита\nна устройстве",
            subtitle: "Ключи и переписка защищены даже если телефон попал в чужие руки.",
            points: [
                PointData(icon: "faceid",
                          color: Color(red: 20/255, green: 184/255, blue: 166/255),
                          text: "**Face ID на seed** — ключи в Keychain под биометрией"),
                PointData(icon: "timer",
                          color: Color(red: 99/255, green: 102/255, blue: 241/255),
                          text: "**Исчезающие сообщения** — авто-удаление локальных копий"),
                PointData(icon: "checkmark.shield.fill",
                          color: Color(red: 16/255, green: 185/255, blue: 129/255),
                          text: "**Подпись контактов** — защита от подмены собеседника (MITM)"),
            ]
        ),
        SlideData(
            icon: "network",
            iconColors: [Color(red: 99/255, green: 102/255, blue: 241/255),
                         Color(red: 168/255, green: 85/255, blue: 247/255)],
            badge: nil,
            title: "Нет серверов.\nСерьёзно.",
            subtitle: "Мы физически не можем прочитать твои сообщения, удалить их или передать кому-либо.",
            points: [
                PointData(icon: "xmark.circle.fill",
                          color: Color(red: 244/255, green: 63/255, blue: 94/255),
                          text: "**Нет центрального сервера** — некого взломать или принудить"),
                PointData(icon: "cube.fill",
                          color: Color(red: 99/255, green: 102/255, blue: 241/255),
                          text: "**Сообщения хранятся на блокчейне** Solana — зашифрованными"),
                PointData(icon: "checkmark.shield.fill",
                          color: Color(red: 16/255, green: 185/255, blue: 129/255),
                          text: "**Полная децентрализация** — не блокируется, не цензурируется"),
            ]
        ),
        SlideData(
            icon: "paperplane.circle.fill",
            iconColors: [Color(red: 245/255, green: 158/255, blue: 11/255),
                         Color(red: 234/255, green: 88/255, blue: 12/255)],
            badge: "10 free",
            title: "Просто\nпиши",
            subtitle: "Комиссии сети мы оплачиваем за тебя. Никакой криптовалюты — только сообщения.",
            points: [
                PointData(icon: "gift.fill",
                          color: Color(red: 16/255, green: 185/255, blue: 129/255),
                          text: "**10 бесплатных сообщений** каждый месяц — сразу, без оплаты"),
                PointData(icon: "star.circle.fill",
                          color: Color(red: 245/255, green: 158/255, blue: 11/255),
                          text: "**PrivaMesh+** — от $5.99/мес: больше сообщений, галочка, 3 аккаунта"),
                PointData(icon: "bag.fill",
                          color: Color(red: 99/255, green: 102/255, blue: 241/255),
                          text: "**Пакеты сообщений** — разовая покупка без подписки"),
            ]
        ),
        SlideData(
            icon: "iphone.and.arrow.forward",
            iconColors: [Color(red: 99/255, green: 102/255, blue: 241/255),
                         Color(red: 168/255, green: 85/255, blue: 247/255)],
            badge: nil,
            title: "Переписка\nтолько у тебя",
            subtitle: "Расшифрованные сообщения хранятся только на этом телефоне — не в облаке и не на сервере.",
            points: [
                PointData(icon: "key.horizontal.fill",
                          color: Color(red: 20/255, green: 184/255, blue: 166/255),
                          text: "**Личность** вернётся по 12 словам на любом устройстве"),
                PointData(icon: "iphone.slash",
                          color: Color(red: 245/255, green: 158/255, blue: 11/255),
                          text: "**История чатов не переедет** на новый телефон — копии есть только здесь"),
                PointData(icon: "lock.shield.fill",
                          color: Color(red: 16/255, green: 185/255, blue: 129/255),
                          text: "**Это защита, а не баг** — даже с твоим seed никто не прочитает старую переписку"),
            ]
        ),
        SlideData(
            icon: "checkmark.seal.fill",
            iconColors: [Color(red: 52/255, green: 211/255, blue: 153/255),
                         Color(red: 34/255, green: 211/255, blue: 238/255)],
            badge: nil,
            title: "Ты готов\nк старту",
            subtitle: "Создай аккаунт или восстанови существующий — займёт меньше минуты.",
            points: [
                PointData(icon: "person.badge.key.fill",
                          color: Color(red: 20/255, green: 184/255, blue: 166/255),
                          text: "**Никакой регистрации** — seed phrase = твой аккаунт навсегда"),
                PointData(icon: "arrow.clockwise.circle.fill",
                          color: Color(red: 99/255, green: 102/255, blue: 241/255),
                          text: "**Восстанавливается** на любом устройстве только по 12 словам"),
                PointData(icon: "at.circle.fill",
                          color: Color(red: 245/255, green: 158/255, blue: 11/255),
                          text: "**Уникальный ник** генерируется автоматически из твоего ключа"),
            ]
        ),
    ]}
}

// MARK: - Data models

private struct SlideData {
    let icon: String
    let iconColors: [Color]
    let badge: String?
    let title: String
    let subtitle: String
    let points: [PointData]
}

private struct PointData {
    let icon: String
    let color: Color
    let text: String
}

// MARK: - Single slide view

private struct OnboardingPage: View {
    let slide: SlideData

    // Entrance + ambient animation state.
    @State private var appear = false      // staggered content reveal
    @State private var pop = false         // icon spring-in
    @State private var pulse = false       // glow breathing
    @State private var spin = false        // orbiting ring

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                animatedIcon

                // Title + subtitle (localized via LocalizedStringKey)
                VStack(spacing: 12) {
                    Text(LocalizedStringKey(slide.title))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                        .multilineTextAlignment(.center)
                        .staggered(appear, index: 1)

                    Text(LocalizedStringKey(slide.subtitle))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)
                        .staggered(appear, index: 2)
                }

                // Bullet points card — each row reveals in sequence
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<slide.points.count, id: \.self) { i in
                        let point = slide.points[i]
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: point.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(point.color)
                                .frame(width: 24)

                            Text(.init(point.text))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.slate700)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                        .staggered(appear, index: 3 + i)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.glass)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(Theme.glassStroke, lineWidth: 1))
            }
            .padding(.horizontal, 28)
            .padding(.top, 64)   // room for the icon's glow/ring (else clipped at top)
            .padding(.bottom, 20)
        }
        .onAppear { runEntrance() }
        .onDisappear {
            // Reset so the entrance replays each time the page scrolls back in.
            appear = false; pop = false
        }
    }

    // MARK: Animated icon (orbiting ring + breathing glow + spring pop)

    private var animatedIcon: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                // Breathing glow halo — kept within the icon frame so the
                // ScrollView doesn't clip it at the top of a slide.
                Circle()
                    .fill(LinearGradient(colors: slide.iconColors,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                    .blur(radius: 20)
                    .opacity(pulse ? 0.55 : 0.30)
                    .scaleEffect(pulse ? 1.06 : 0.92)

                // Orbiting conic ring
                Circle()
                    .stroke(
                        AngularGradient(colors: slide.iconColors + [slide.iconColors.first ?? .clear],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 7]))
                    .frame(width: 112, height: 112)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .opacity(0.7)

                // Glass disc + icon
                Circle()
                    .fill(Theme.glass)
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(Theme.glassStroke, lineWidth: 1))

                Image(systemName: slide.icon)
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                    .foregroundStyle(LinearGradient(colors: slide.iconColors,
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 120, height: 120)
            .scaleEffect(pop ? 1 : 0.5)
            .opacity(pop ? 1 : 0)
            .rotationEffect(.degrees(pop ? 0 : -25))

            if let badge = slide.badge {
                Text(badge)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(LinearGradient(colors: slide.iconColors,
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                    .scaleEffect(appear ? 1 : 0.4)
                    .opacity(appear ? 1 : 0)
            }
        }
    }

    private func runEntrance() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { pop = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { appear = true }
        // Ambient loops (idempotent — guarded so they don't stack on replays).
        if !pulse { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true } }
        if !spin  { withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) { spin = true } }
    }
}

// MARK: - Staggered reveal modifier

private extension View {
    /// Fade + slide-up reveal, delayed by `index` for a cascading effect.
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
}
