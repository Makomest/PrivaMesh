//
//  BackgroundRefresh.swift
//  privamesh
//
//  Wakes the app periodically (BGAppRefreshTask) to run one polling cycle so
//  new messages / incoming transactions can fire local notifications without
//  the app being open. iOS decides the actual cadence — earliestBeginDate is
//  only a hint and delivery is best-effort, not guaranteed.
//

import Foundation
import BackgroundTasks
import SwiftData

enum BackgroundRefresh {
    /// Must match the entry in Info.plist → BGTaskSchedulerPermittedIdentifiers.
    static let taskIdentifier = "com.privamesh.refresh"

    /// Register the handler. Call once, before the app finishes launching.
    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false); return
            }
            handle(refreshTask, container: container)
        }
    }

    /// Ask iOS to schedule the next refresh. Call when entering the background.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // hint only
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handling

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        schedule() // chain the next wake-up immediately

        let work = Task {
            await runPoll(container: container)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    @MainActor
    private static func runPoll(container: ModelContainer) async {
        // Identity lives in Keychain — reachable without the full app graph.
        guard let address = (try? KeychainStorage.read(.publicKey)) ?? nil,
              !address.isEmpty else { return }

        let identity = MessagingIdentityManager()
        identity.bind(to: address)   // use this account's messaging keys
        let rpc      = SolanaRPCService()
        let polling  = PollingService()

        await polling.pollOnceForBackground(
            myAddress: address,
            identity:  identity,
            rpc:       rpc,
            context:   container.mainContext
        )
    }
}
