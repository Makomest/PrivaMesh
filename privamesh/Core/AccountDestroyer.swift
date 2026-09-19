//
//  AccountDestroyer.swift
//  privamesh
//
//  Erasing an account from this device, for the duress code.
//
//  Everything local goes: the messages and contacts in SwiftData, every key this
//  app keeps in the Keychain, every default it wrote, and the notifications
//  already sitting in Notification Center. What is left has to be a phone that
//  looks like the app was installed a minute ago and never used.
//
//  What it cannot do is reach the chain. Ciphertext already published stays
//  there for good; without the keys nobody can read it, but the fact that an
//  address sent messages is public and permanent. The UI has to say that rather
//  than imply this button unsends anything.
//

import Foundation
import SwiftData
import SQLite3
import UserNotifications

enum AccountDestroyer {

    /// Wipe everything this device holds — every account, not just the active one.
    ///
    /// Deliberately silent and ordered so the visible things go first: if the
    /// process is killed halfway, what is left on screen must not still be a
    /// readable conversation.
    ///
    /// The Keychain is cleared by service rather than key by key. Per-account
    /// items are named after the wallet address (`privamesh.seed.<pubkey>`,
    /// `privamesh.messaging.identity.<pubkey>`, the relay and gas-wallet keys),
    /// so no hard-coded list of names can be complete — and an incomplete one is
    /// what let a "wiped" device hand its seed phrases straight back.
    @MainActor
    static func destroy(context: ModelContext,
                        wallet: WalletManager,
                        passcode: PasscodeManager,
                        biometry: BiometryService,
                        accounts: AccountManager,
                        identity: MessagingIdentityManager) {
        deleteMessages(context: context)
        scrubStoreFiles(context.container)
        clearNotifications()
        clearDefaults()

        // In-memory state of the services that cache it. Their stored copies go
        // with the Keychain sweep below; these calls stop the running app from
        // writing any of it back.
        let addresses = accounts.accounts.map(\.publicKeyBase58)
        accounts.removeAll()
        identity.wipeAll(addresses: addresses)
        wallet.wipe()
        passcode.wipe()
        biometry.disable()

        KeychainStorage.wipeEverything()
    }

    /// Remove every stored message and contact.
    ///
    /// Contacts go first and the cascade takes their messages with them. Order is
    /// not a detail: `ChatMessage.contact` is a mandatory inverse, so deleting the
    /// messages on their own is refused outright — "Constraint trigger violation:
    /// Batch delete failed due to mandatory OTO nullify inverse on
    /// ChatMessage/contact" — and the old wipe fell through to a per-object pass
    /// that took about six seconds for five thousand messages. Deleting contacts
    /// is one statement and clears both tables in hundredths of a second.
    ///
    /// `ModelContainer.deleteAllData()` looks like the obvious way to do this and
    /// must not be used: it empties the store behind the contexts that are still
    /// live, and the next insert-and-save on the app's own context trips a
    /// SwiftData assertion — a crash, not a thrown error, so nothing can catch
    /// it. On the device that landed as "create an account after a wipe and the
    /// app dies at the first screen".
    ///
    /// A partial delete would leave readable messages behind, which is the one
    /// outcome this feature exists to prevent, so the fast path is followed by a
    /// count that must be zero and a per-object pass if it is not.
    @MainActor
    private static func deleteMessages(context: ModelContext) {
        try? context.delete(model: Contact.self)
        // Rows no contact owns any more (legacy imports, interrupted inserts).
        try? context.delete(model: ChatMessage.self)
        try? context.save()

        let leftover = ((try? context.fetchCount(FetchDescriptor<ChatMessage>())) ?? 0)
            + ((try? context.fetchCount(FetchDescriptor<Contact>())) ?? 0)
        guard leftover > 0 else { return }

        let messages = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []
        messages.forEach(context.delete)
        let contacts = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        contacts.forEach(context.delete)
        try? context.save()
    }

    /// Deleting a row is not erasing it.
    ///
    /// SQLite keeps the old bytes: in the write-ahead log until something
    /// checkpoints it, and in freed pages of the database file after that. A
    /// device imaged after a duress wipe would still yield message text. The
    /// checkpoint flushes the log and truncates it to nothing, VACUUM rewrites
    /// the database without the freed pages, and the second checkpoint clears
    /// the log VACUUM itself wrote.
    private static func scrubStoreFiles(_ container: ModelContainer) {
        for url in container.configurations.map(\.url)
        where FileManager.default.fileExists(atPath: url.path) {
            var handle: OpaquePointer?
            guard sqlite3_open(url.path, &handle) == SQLITE_OK, let db = handle else {
                if let handle { sqlite3_close(handle) }
                continue
            }
            // The app's own connection may still be finishing a write.
            sqlite3_busy_timeout(db, 3_000)
            for statement in ["PRAGMA wal_checkpoint(TRUNCATE)", "VACUUM", "PRAGMA wal_checkpoint(TRUNCATE)"] {
                sqlite3_exec(db, statement, nil, nil, nil)
            }
            sqlite3_close(db)
        }
    }

    /// Notifications already delivered stay in Notification Center after the app
    /// is wiped, and a message notification names the sender. Left there, they
    /// are both a list of contacts and proof the app was in use.
    private static func clearNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    /// Every default this app has ever written.
    ///
    /// Swept by prefix rather than by name for the same reason as the Keychain:
    /// the interesting ones are suffixed with the wallet address
    /// (`privamesh.avatars.owned.<pubkey>`, `privamesh.market.ownedNicks.<pubkey>`,
    /// `privamesh.discovery.publishedNick.v2.<pubkey>`), so a list of names
    /// leaves the address itself sitting in the key.
    ///
    /// `privamesh.onboardingDone` goes with them on purpose: keeping it sent the
    /// wiped app to the Welcome screen while a genuine first launch starts at the
    /// onboarding slides, and that difference is visible to whoever is holding
    /// the phone.
    private static func clearDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("privamesh.") {
            defaults.removeObject(forKey: key)
        }
    }
}
