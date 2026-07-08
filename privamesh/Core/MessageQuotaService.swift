//
//  MessageQuotaService.swift
//  privamesh
//
//  Client-side mirror of the user's message allowance. Every message is a Solana
//  transaction whose fee is paid by the app-operated shared gas wallet through
//  the relay; the relay is the *authoritative* quota gate. This service is the
//  on-device UX mirror: it shows the remaining balance and lets the UI block or
//  paywall a send before hitting the network.
//
//  Two sources of allowance, spent in this order:
//    1. Subscription monthly allowance (Plus 1200 / Pro 2000), resets each month.
//    2. Consumable pack credits (100 / 500 / 1500), never expire.
//
//  Allowance is per Apple ID (subscriptions/packs are per Apple ID), so counters
//  are stored globally on the device, not per wallet account.
//

import Foundation

@Observable
final class MessageQuotaService {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let periodStart = "privamesh.quota.periodStart"
        static let usedThisPeriod = "privamesh.quota.usedThisPeriod"
        static let packCredits = "privamesh.quota.packCredits"
    }

    /// Supplies the current membership tier (wired to SubscriptionManager).
    var tierProvider: () -> PlusTier = { .none }

    /// Whether the active account is the device's first one. Only the first
    /// account gets the free tier; extra accounts get 0 free messages, so making
    /// more accounts can't farm the free allowance. (Wired to AccountManager.)
    var isFirstAccountActive: () -> Bool = { true }

    /// Small free allowance so brand-new users can try sending before paying.
    static let freeMonthlyMessages = 10

    // MARK: - Persisted counters

    // Stored (not computed-over-UserDefaults) so @Observable tracks mutations and
    // SwiftUI updates live; each is persisted on change via didSet.
    private var usedThisPeriod: Int {
        didSet { defaults.set(usedThisPeriod, forKey: Key.usedThisPeriod) }
    }

    /// Non-expiring credits from consumable packs.
    private(set) var packCredits: Int {
        didSet { defaults.set(packCredits, forKey: Key.packCredits) }
    }

    private var periodStart: Date? {
        didSet { defaults.set(periodStart, forKey: Key.periodStart) }
    }

    init() {
        usedThisPeriod = defaults.integer(forKey: Key.usedThisPeriod)
        packCredits = defaults.integer(forKey: Key.packCredits)
        periodStart = defaults.object(forKey: Key.periodStart) as? Date
        rolloverIfNeeded()
    }

    // MARK: - Allowance math

    /// Monthly allowance for the active tier. Paid tiers apply to any account
    /// (subscription covers up to 3). The free tier is limited to the device's
    /// first account so extra accounts can't farm free messages.
    private var monthlyAllowance: Int {
        let tier = tierProvider()
        if tier != .none { return tier.monthlyMessages }
        return isFirstAccountActive() ? Self.freeMonthlyMessages : 0
    }

    /// Messages left in the current monthly bucket.
    var subscriptionRemaining: Int {
        rolloverIfNeeded()
        return max(0, monthlyAllowance - usedThisPeriod)
    }

    /// Total messages the user can send right now.
    var remaining: Int { subscriptionRemaining + packCredits }

    /// Whether the user can send at least one message.
    var canSend: Bool { remaining > 0 }

    // MARK: - Mutations

    /// Spend one message: monthly bucket first, then pack credits.
    /// Returns false when nothing is left (caller should paywall).
    @discardableResult
    func consume() -> Bool {
        rolloverIfNeeded()
        if monthlyAllowance - usedThisPeriod > 0 {
            usedThisPeriod += 1
            return true
        }
        if packCredits > 0 {
            packCredits -= 1
            return true
        }
        return false
    }

    /// Credit consumable-pack messages (called from SubscriptionManager).
    func creditPack(_ messages: Int) {
        guard messages > 0 else { return }
        packCredits += messages
    }

    // MARK: - Monthly rollover

    /// Reset the monthly bucket when a new calendar month begins.
    private func rolloverIfNeeded() {
        let now = Date()
        let cal = Calendar.current
        if let start = periodStart {
            if !cal.isDate(start, equalTo: now, toGranularity: .month) {
                usedThisPeriod = 0
                periodStart = now
            }
        } else {
            periodStart = now
        }
    }
}
