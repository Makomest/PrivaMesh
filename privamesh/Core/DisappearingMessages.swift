//
//  DisappearingMessages.swift
//  privamesh
//
//  Local auto-purge. On-chain ciphertext is immutable, but the decrypted copy
//  lives in SwiftData forever — a privacy risk on a seized/shared device. When a
//  contact has a disappear window set, messages older than it are deleted from
//  the local store (the chain memo stays, but it's unreadable without the keys).
//

import Foundation
import SwiftData

enum DisappearingMessages {
    /// User-selectable windows (seconds). 0 = off.
    static let options: [(label: String, seconds: Int)] = [
        ("Выкл", 0),
        ("1 час", 3_600),
        ("1 день", 86_400),
        ("1 неделя", 604_800),
    ]

    static func label(for seconds: Int) -> String {
        String(localized: String.LocalizationValue(options.first { $0.seconds == seconds }?.label ?? "Выкл"))
    }

    /// Localized label for an option (for menus/pickers).
    static func localizedLabel(_ raw: String) -> String {
        String(localized: String.LocalizationValue(raw))
    }

    /// Delete expired local messages for every contact with a window set.
    @MainActor
    static func purge(context: ModelContext) {
        let contacts = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        let now = Date()
        var deleted = false
        for c in contacts where c.disappearSeconds > 0 {
            let cutoff = now.addingTimeInterval(-Double(c.disappearSeconds))
            for m in c.messages where m.sentAt < cutoff {
                context.delete(m)
                deleted = true
            }
        }
        if deleted { try? context.save() }
    }

    /// Purge a single contact (e.g. when its chat opens).
    @MainActor
    static func purge(_ contact: Contact, context: ModelContext) {
        guard contact.disappearSeconds > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(contact.disappearSeconds))
        var deleted = false
        for m in contact.messages where m.sentAt < cutoff {
            context.delete(m)
            deleted = true
        }
        if deleted { try? context.save() }
    }
}
