//
//  PrivacyPolicyView.swift
//  privamesh
//

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            PastelBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    policySection(
                        title: "Overview",
                        body: "PrivaMesh is a private, end-to-end encrypted messenger. We do not operate account servers, collect personal data, or have access to your messages."
                    )
                    policySection(
                        title: "Data We Do Not Collect",
                        body: "We do not collect names, email addresses, phone numbers, IP addresses, location data, device identifiers, or usage analytics. We have no backend servers."
                    )
                    policySection(
                        title: "Data Stored on Your Device",
                        body: "Your recovery phrase, passcode hash, and cryptographic identity keys are stored exclusively in the iOS Keychain on your device. Messages and contacts are stored in the local SwiftData database. Nothing leaves your device except encrypted messages sent over our relay."
                    )
                    policySection(
                        title: "Message Delivery",
                        body: "Messages are delivered as encrypted ciphertext over a public, decentralized transport. The ciphertext is visible on the transport but is unreadable without the recipient's keys, and it references only single-use delivery addresses, never personal identifiers. This delivered data is immutable and outside our control; we cannot delete it."
                    )
                    policySection(
                        title: "Encryption",
                        body: "All messages use the Double Ratchet protocol — the same family used by leading secure messengers — with X3DH key agreement. Keys are derived per-session and rotated with every message. PrivaMesh has no ability to read your messages."
                    )
                    policySection(
                        title: "StoreKit (PrivaMesh+)",
                        body: "Subscription purchases are handled entirely by Apple via StoreKit 2. We receive only a transaction verification token. Apple's privacy policy governs payment data."
                    )
                    policySection(
                        title: "Changes",
                        body: "Any material changes to this policy will be announced in the app before taking effect."
                    )
                    policySection(
                        title: "Contact",
                        body: "Questions: privamesh@proton.me"
                    )
                    Text("Last updated: June 2026")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.slate400)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Privacy Policy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.slate800)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(Theme.slate600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
