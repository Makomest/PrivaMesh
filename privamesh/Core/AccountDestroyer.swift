//
//  AccountDestroyer.swift
//  privamesh
//
//  Erasing an account from this device, for the duress code.
//
//  Everything local goes: the messages and contacts in SwiftData, the seed and
//  keys in the Keychain, both passcodes, biometry, and the defaults that would
//  otherwise leave a name or a nickname behind.
//
//  What it cannot do is reach the chain. Ciphertext already published stays
//  there for good; without the keys nobody can read it, but the fact that an
//  address sent messages is public and permanent. The UI has to say that rather
//  than imply this button unsends anything.
//

import Foundation
import SwiftData

enum AccountDestroyer {

    /// Wipe everything this device holds for the current account.
    ///
    /// Deliberately silent and ordered so the visible things go first: if the
    /// process is killed halfway, what is left on screen must not still be a
    /// readable conversation.
    @MainActor
    static func destroy(context: ModelContext,
                        wallet: WalletManager,
                        passcode: PasscodeManager,
                        biometry: BiometryService) {
        deleteMessages(context: context)
        clearDefaults()

        wallet.wipe()          // seed phrase and keys out of the Keychain
        passcode.wipe()        // both codes
        biometry.disable()
    }

    /// Remove every stored message and contact.
    ///
    /// SwiftData's batch delete is used where it works, with a per-object pass as
    /// the fallback: a partial delete here would leave readable messages behind,
    /// which is the one outcome this whole feature exists to prevent.
    @MainActor
    private static func deleteMessages(context: ModelContext) {
        do {
            try context.delete(model: ChatMessage.self)
            try context.delete(model: Contact.self)
            try context.save()
        } catch {
            let messages = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []
            messages.forEach(context.delete)
            let contacts = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
            contacts.forEach(context.delete)
            try? context.save()
        }
    }

    /// Defaults that describe the person rather than the app.
    ///
    /// Anything keyed by wallet address is dropped wholesale: the address itself
    /// is about to be unrecoverable, so a leftover key is only a trace of who was
    /// here.
    private static func clearDefaults() {
        let defaults = UserDefaults.standard
        let prefixes = [
            "privamesh.profile.",
            "privamesh.nickname",
            "privamesh.passcode.",
            "privamesh.quota.",
            "privamesh.lastAccount",
            "privamesh.seedBiometricLock",
        ]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
