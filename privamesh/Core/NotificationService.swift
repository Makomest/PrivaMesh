//
//  NotificationService.swift
//  privamesh
//
//  Local notifications. PrivaMesh is server-less, so there is no push — these
//  fire from the polling loop while the app is running (and shortly after it is
//  backgrounded). Content is kept generic (no decrypted text) for privacy.
//
//  Singleton because notification posting is app-global and the polling/market
//  code that triggers it is deep in the object graph.
//

import Foundation
import UserNotifications
import SwiftData

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() { super.init() }

    /// Contact id of the chat currently open on screen. Messages from this
    /// contact don't fire a notification (you're already looking at the chat).
    var activeChatId: String?

    // MARK: - User preferences (persisted)

    private static let muteAllKey = "privamesh.notif.muteAll"
    private static let previewKey = "privamesh.notif.preview"

    /// "Не беспокоить" — suppress ALL local notifications.
    var muteAll: Bool {
        get { UserDefaults.standard.bool(forKey: Self.muteAllKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.muteAllKey) }
    }

    /// Show the sender's name in message notifications (default on).
    var showPreview: Bool {
        get { UserDefaults.standard.object(forKey: Self.previewKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.previewKey) }
    }

    /// Call once at launch to route foreground banners through us.
    func bootstrap() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Event helpers

    func notifyMessage(from name: String) {
        post(title: String(localized: "Новое сообщение"),
             body: showPreview ? String(localized: "от \(name)") : String(localized: "Зашифрованное сообщение"))
    }

    func notifyIncomingTransaction(amountSOL: Double?) {
        let body = amountSOL.map { String(localized: "Получено +\(String(format: "%.4f", $0)) SOL") }
            ?? String(localized: "Получен перевод")
        post(title: String(localized: "Входящая транзакция"), body: body)
    }

    func notifyNicknameSold(nickname: String, priceSOL: Double) {
        post(title: String(localized: "Твой ник купили"),
             body: String(localized: "«\(nickname)» продан за \(formatSOL(priceSOL))"))
    }

    func notifyAvatarSold(name: String, priceSOL: Double) {
        post(title: String(localized: "Твой NFT-аватар купили"),
             body: String(localized: "«\(name)» продан за \(formatSOL(priceSOL))"))
    }

    // MARK: - Internals

    private func post(title: String, body: String) {
        guard !muteAll else { return }   // "Не беспокоить"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)   // dropped silently if unauthorized
    }

    private func formatSOL(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v)) SOL" : String(format: "%.2g SOL", v)
    }

    // MARK: - App-icon badge (unread count on the home screen)

    @MainActor
    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }

    /// Recompute unread incoming messages for the active account and set the
    /// app-icon badge. Call after polling, on read, and on foreground.
    @MainActor
    func refreshBadge(context: ModelContext, myAddress: String) {
        let desc = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { !$0.isOutgoing && !$0.isRead })
        let unread = ((try? context.fetch(desc)) ?? []).filter {
            let owner = $0.contact?.ownerAddress ?? ""
            return owner == myAddress || owner.isEmpty
        }.count
        setBadge(unread)
    }

    // Show banners even while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
