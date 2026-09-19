//
//  DuressWipeTests.swift
//  privameshTests
//
//  What the duress code leaves behind.
//
//  The code itself was correct long before the wipe it triggers was: entering it
//  deleted the chats and the active account's slot, and left every account's seed
//  phrase, messaging identity and relay token in the Keychain, the account list
//  in UserDefaults, and the message text in the store's write-ahead log. The app
//  showed a Welcome screen; the account behind it could be switched back on.
//
//  These tests hold the wipe to what the feature claims: nothing of this account
//  stays on the device, and nothing on screen says a wipe happened.
//
//  Nested inside PasscodeStorageTests for the same reason as DuressCodeTests:
//  the suites share Keychain items and must not interleave.
//

import Testing
import Foundation
import Security
import SwiftData
@testable import privamesh

extension PasscodeStorageTests {

@Suite("Duress wipe", .serialized)
struct DuressWipeTests {

    private func keychainExists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// Non-overlapping occurrences of `needle` in `haystack`.
    private func occurrences(of needle: Data, in haystack: Data) -> Int {
        var count = 0
        var start = haystack.startIndex
        while let range = haystack.range(of: needle, in: start..<haystack.endIndex) {
            count += 1
            start = range.upperBound
        }
        return count
    }

    /// An account set up the way the app sets one up: seed in the Keychain under
    /// its own address, a derived messaging identity, a sealed ratchet state, the
    /// defaults that name it.
    @MainActor
    private func installedAccount(context: ModelContext)
    async throws -> (AccountManager, MessagingIdentityManager, WalletManager, WalletAccount) {
        let accounts = AccountManager()
        accounts.removeAll()
        let identity = MessagingIdentityManager()
        accounts.onSeedStored = { pub, phrase in identity.provision(address: pub, seedPhrase: phrase) }

        let account = try await accounts.importAccount(phrase: DemoContent.demoPhrase, name: "Wipe test")
        identity.bind(to: account.publicKeyBase58)
        _ = try identity.getOrCreate()

        let wallet = WalletManager()
        wallet.activate(account: account, seedPhrase: DemoContent.demoPhrase)

        UserDefaults.standard.set(account.publicKeyBase58, forKey: "privamesh.activeAccountPubkey")
        UserDefaults.standard.set(true, forKey: "privamesh.onboardingDone")
        UserDefaults.standard.set(["mesh-01"], forKey: "privamesh.avatars.owned.\(account.publicKeyBase58)")

        let contact = Contact(id: "peer", displayName: "peer", prekeyBundleBase64: "")
        contact.sessionData = SessionVault.seal(Data(#"{"root":"secret"}"#.utf8))
        context.insert(contact)
        let message = ChatMessage(id: "sig", body: "secret text",
                                  isOutgoing: false, sentAt: .now, status: "received")
        message.contact = contact
        context.insert(message)
        try context.save()

        return (accounts, identity, wallet, account)
    }

    /// The one that mattered: after the wipe the account must not be rebuildable
    /// from anything left on the device — least of all by the app itself.
    @MainActor
    @Test func nothingOfTheAccountSurvives() async throws {
        let container = try ModelContainer(
            for: Contact.self, ChatMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let (accounts, identity, wallet, account) = try await installedAccount(context: context)
        let pub = account.publicKeyBase58

        let passcode = PasscodeManager()
        passcode.wipe()
        try passcode.setPasscode("1234", length: 4)
        #expect(passcode.setDuressPasscode("9999", currentPasscode: "1234"))
        let biometry = BiometryService()

        #expect(passcode.check("9999") == .duress)
        AccountDestroyer.destroy(context: context, wallet: wallet, passcode: passcode,
                                 biometry: biometry, accounts: accounts, identity: identity)

        // Keychain: every item, including the ones keyed by wallet address.
        #expect(keychainExists(service: "com.privamesh.wallet", account: "privamesh.seed.\(pub)") == false)
        #expect(keychainExists(service: "com.privamesh.wallet", account: "privamesh.messaging.identity.\(pub)") == false)
        #expect(keychainExists(service: "com.privamesh.wallet", account: "privamesh.relay.token.\(pub)") == false)
        #expect(keychainExists(service: "com.privamesh.wallet", account: "privamesh.seedPhrase") == false)
        #expect(keychainExists(service: "com.privamesh.wallet", account: "privamesh.publicKey") == false)
        #expect(keychainExists(service: "com.privamesh.sessionvault", account: "privamesh.sessionVaultKey") == false)

        // Defaults, including the per-address ones whose KEY is the address.
        #expect(UserDefaults.standard.data(forKey: "privamesh.accounts.v2") == nil)
        #expect(UserDefaults.standard.string(forKey: "privamesh.activeAccountPubkey") == nil)
        #expect(UserDefaults.standard.object(forKey: "privamesh.avatars.owned.\(pub)") == nil)

        // A fresh launch must find nothing to switch back to.
        let relaunched = AccountManager()
        #expect(relaunched.accounts.isEmpty)
        #expect(relaunched.seedPhrase(for: pub) == nil)

        let relaunchedWallet = WalletManager()
        #expect(relaunchedWallet.state == .noWallet)

        let relaunchedIdentity = MessagingIdentityManager()
        relaunchedIdentity.bind(to: pub)
        #expect(relaunchedIdentity.identity == nil)

        // And the ratchet key is gone, so any sealed state that outlives the rows
        // is noise rather than a conversation.
        let sealed = SessionVault.seal(Data(#"{"root":"secret"}"#.utf8))
        SessionVault.wipe()
        #expect(SessionVault.open(sealed) == nil)

        #expect((try? context.fetch(FetchDescriptor<ChatMessage>()))?.isEmpty == true)
        #expect((try? context.fetch(FetchDescriptor<Contact>()))?.isEmpty == true)

        passcode.wipe()
    }

    /// The onboarding flag goes with everything else, so the wiped app starts
    /// where a never-launched one starts. Keeping it sent the user to Welcome and
    /// a real first launch to the slides — a difference visible to whoever made
    /// them unlock the phone.
    @MainActor
    @Test func theAppLooksNeverLaunched() async throws {
        let container = try ModelContainer(
            for: Contact.self, ChatMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let (accounts, identity, wallet, _) = try await installedAccount(context: context)

        let passcode = PasscodeManager()
        passcode.wipe()
        try passcode.setPasscode("1234", length: 4)
        let biometry = BiometryService()

        AccountDestroyer.destroy(context: context, wallet: wallet, passcode: passcode,
                                 biometry: biometry, accounts: accounts, identity: identity)

        #expect(UserDefaults.standard.bool(forKey: "privamesh.onboardingDone") == false)
        #expect(passcode.isPasscodeConfirmedAbsent)
        #expect(passcode.isDuressSet == false)
        passcode.wipe()
    }

    /// Deleting a row is not erasing it: SQLite keeps the bytes in the
    /// write-ahead log, and then in freed pages. A device imaged after the wipe
    /// yielded message text, 95 copies of it in the first run of this test.
    @MainActor
    @Test func noMessageTextIsLeftInTheStoreFiles() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duress-wipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("messages.store")
        let container = try ModelContainer(for: Contact.self, ChatMessage.self,
                                           configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)

        let marker = "MARKER-7f3c2a-PLAINTEXT-MESSAGE-BODY"
        let contact = Contact(id: "peer", displayName: "peer", prekeyBundleBase64: "")
        context.insert(contact)
        for i in 0..<50 {
            let message = ChatMessage(id: "sig-\(i)", body: "\(marker) #\(i)",
                                      isOutgoing: false, sentAt: .now, status: "received")
            message.contact = contact
            context.insert(message)
        }
        try context.save()

        let accounts = AccountManager()
        let identity = MessagingIdentityManager()
        let passcode = PasscodeManager()
        AccountDestroyer.destroy(context: context, wallet: WalletManager(), passcode: passcode,
                                 biometry: BiometryService(), accounts: accounts, identity: identity)

        var found = 0
        for suffix in ["", "-wal", "-shm"] {
            guard let data = FileManager.default.contents(atPath: storeURL.path + suffix) else { continue }
            found += occurrences(of: Data(marker.utf8), in: data)
        }
        #expect(found == 0, "message text still readable in the store files: \(found) copies")
        passcode.wipe()
    }

    /// The app has to keep working after the wipe.
    ///
    /// `ModelContainer.deleteAllData()` was the fast way to empty the store and it
    /// emptied it behind the live context: the next insert-and-save tripped a
    /// SwiftData assertion, which is a crash and not a thrown error. On the phone
    /// that read as "wipe, create an account, and the app dies as the main screen
    /// appears" — `MainTabView.ensureSelfContact` saving the Saved Messages
    /// contact.
    @MainActor
    @Test func theStoreIsStillUsableAfterAWipe() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duress-reuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = try ModelContainer(
            for: Contact.self, ChatMessage.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("reuse.store")))
        let context = container.mainContext

        let address = "AoxpJiPLreuseProbeAddress"
        let before = Contact(id: address, displayName: "Saved Messages", prekeyBundleBase64: "")
        before.isSelf = true
        context.insert(before)
        let message = ChatMessage(id: "sig", body: "secret text",
                                  isOutgoing: true, sentAt: .now, status: "sent")
        message.contact = before
        context.insert(message)
        try context.save()

        let passcode = PasscodeManager()
        AccountDestroyer.destroy(context: context, wallet: WalletManager(), passcode: passcode,
                                 biometry: BiometryService(), accounts: AccountManager(),
                                 identity: MessagingIdentityManager())

        // Exactly what MainTabView.ensureSelfContact does on the next account.
        let descriptor = FetchDescriptor<Contact>(predicate: #Predicate { $0.id == address })
        #expect((try? context.fetchCount(descriptor)) == 0)
        let after = Contact(id: address, displayName: "Saved Messages", prekeyBundleBase64: "")
        after.isSelf = true
        context.insert(after)
        try context.save()

        #expect((try? context.fetchCount(descriptor)) == 1)
        #expect((try? context.fetchCount(FetchDescriptor<ChatMessage>())) == 0)
        passcode.wipe()
    }

    /// The wipe runs on the main thread before the screen changes, so its cost is
    /// visible as a freeze. Row-by-row deletion took about six seconds for this
    /// many messages; the bound is loose enough for a busy machine and tight
    /// enough to catch a return to that.
    @MainActor
    @Test func theWipeIsQuickEnoughToGoUnnoticed() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duress-cost-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = try ModelContainer(
            for: Contact.self, ChatMessage.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("cost.store")))
        let context = ModelContext(container)

        let contact = Contact(id: "peer", displayName: "peer", prekeyBundleBase64: "")
        context.insert(contact)
        for i in 0..<5_000 {
            let message = ChatMessage(id: "sig-\(i)", body: String(repeating: "x", count: 200),
                                      isOutgoing: false, sentAt: .now, status: "received")
            message.contact = contact
            context.insert(message)
        }
        try context.save()

        let passcode = PasscodeManager()
        let started = Date()
        AccountDestroyer.destroy(context: context, wallet: WalletManager(), passcode: passcode,
                                 biometry: BiometryService(), accounts: AccountManager(),
                                 identity: MessagingIdentityManager())
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < 2.0, "wiping 5000 messages took \(String(format: "%.2f", elapsed))s on the main thread")
        #expect((try? context.fetch(FetchDescriptor<ChatMessage>()))?.isEmpty == true)
        passcode.wipe()
    }
}

}
