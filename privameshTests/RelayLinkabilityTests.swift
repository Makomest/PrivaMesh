//
//  RelayLinkabilityTests.swift
//  privameshTests
//
//  Reported by Mudit (mudit.raj32@gmail.com) on 26 August 2026.
//
//  The blind-token design exists so the relay cannot connect a purchase to a
//  send: `/issue` carries an Apple receipt, `/send` carries only an unlinkable
//  token. HTTP undoes that by itself unless it is told not to - a cookie set
//  during issuance comes back during the send, and so does a cached ETag.
//

import Testing
import Foundation
@testable import privamesh

@Suite("Relay linkability")
struct RelayLinkabilityTests {

    /// Whatever the relay says, nothing about one request may reach the next.
    @Test func theSharedSessionKeepsNoServerChosenState() {
        let session = PrivateNetwork.sessionForTesting
        let configuration = session.configuration

        #expect(configuration.httpCookieStorage == nil, "a cookie set at /issue would come back at /send")
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.urlCache == nil, "an ETag is a cookie by another name")
    }

    /// The system cookie jar must not be reachable from this session either.
    @Test func theSystemCookieJarIsNotUsed() {
        let configuration = PrivateNetwork.sessionForTesting.configuration
        #expect(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
    }
}
