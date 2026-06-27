//
//  AppRouter.swift
//  privamesh
//

import SwiftUI

@Observable
final class AppRouter {
    enum Route {
        case onboarding
        case welcome
        case createWallet
        case seedPhraseDisplay
        case seedPhraseConfirm
        case importWallet
        case passcodeSetup
        case biometryPrompt
        case passcodeEnter
        case main
    }

    var route: Route = .welcome

    func go(to route: Route) {
        self.route = route
    }
}
