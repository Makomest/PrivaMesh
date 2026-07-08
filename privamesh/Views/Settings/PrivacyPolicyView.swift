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
                        body: "PrivaMesh is a self-custodial, decentralized messaging application. We do not operate servers, collect personal data, or have access to your messages or wallet."
                    )
                    policySection(
                        title: "Data We Do Not Collect",
                        body: "We do not collect names, email addresses, phone numbers, IP addresses, location data, device identifiers, or usage analytics. We have no backend servers."
                    )
                    policySection(
                        title: "Data Stored on Your Device",
                        body: "Your seed phrase, passcode hash, and cryptographic identity keys are stored exclusively in the iOS Keychain on your device. Messages and contacts are stored in the local SwiftData database. Nothing leaves your device except encrypted messages sent to the Solana blockchain."
                    )
                    policySection(
                        title: "Solana Blockchain",
                        body: "Messages are transmitted as encrypted memo fields on Solana transactions. The ciphertext is permanently stored on the Solana blockchain and visible to anyone — however, only the intended recipient can decrypt the content. Transactions reference only Solana account addresses, never personal identifiers."
                    )
                    policySection(
                        title: "Arweave / Irys (Photo Sharing)",
                        body: "When you send a photo, it is encrypted on-device with AES-256-GCM before upload. The encrypted bytes are stored permanently on Arweave. Only the recipient receives the decryption key (via the encrypted Solana memo). No cleartext photo ever leaves your device."
                    )
                    policySection(
                        title: "Encryption",
                        body: "All messages use the Double Ratchet protocol (as used in Signal) with X3DH key agreement. Keys are derived per-session and rotated with every message. PrivaMesh has no ability to read your messages."
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
                        body: "Questions: privacy@privamesh.xyz"
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
