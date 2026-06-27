//
//  SolanaRPCService.swift
//  privamesh
//
//  Manages a pool of Solana RPC endpoints with automatic rotation on failure.
//  Helius (premium) is the primary endpoint; public nodes are fallbacks.
//

import Foundation
import SolanaSwift

@Observable
final class SolanaRPCService {
    // MARK: - Developer configuration
    //
    // Drop in your own Helius API key (free at https://helius.dev). Placeholder
    // here - the app falls back to the public Solana RPC endpoints below, and
    // users can set a custom RPC in Settings. Read-only RPC only; never a private key.
    private static let heliusAPIKey = "YOUR_HELIUS_API_KEY"

    /// User-supplied custom RPC URL. When set, it's used first; the app's
    /// defaults remain as fallbacks. Persisted in UserDefaults.
    private static let customKey = "privamesh.rpc.custom"

    private static func buildEndpoints() -> [APIEndPoint] {
        var list: [APIEndPoint] = []
        // 1. User's own RPC (highest priority).
        if let custom = UserDefaults.standard.string(forKey: customKey),
           !custom.isEmpty, URL(string: custom) != nil {
            list.append(APIEndPoint(address: custom, network: .mainnetBeta))
        }
        // 2. App default (Helius).
        if heliusAPIKey != "YOUR_HELIUS_API_KEY" {
            list.append(APIEndPoint(
                address: "https://mainnet.helius-rpc.com/?api-key=\(heliusAPIKey)",
                network: .mainnetBeta
            ))
        }
        // 3. Public fallbacks.
        list += [
            APIEndPoint(address: "https://api.mainnet-beta.solana.com", network: .mainnetBeta),
            APIEndPoint(address: "https://solana-rpc.publicnode.com",   network: .mainnetBeta),
        ]
        return list
    }

    private(set) var endpoints: [APIEndPoint]
    private(set) var currentIndex: Int = 0
    private(set) var client: JSONRPCAPIClient

    /// The custom RPC the user configured, if any.
    var customRPC: String? {
        let s = UserDefaults.standard.string(forKey: Self.customKey)
        return (s?.isEmpty == false) ? s : nil
    }

    var currentEndpoint: APIEndPoint { endpoints[currentIndex] }

    /// Estimated fee for a single memo message in lamports (updated by refreshFee).
    /// Base 5000 (1 signature) + priority fee (~100 lamports).
    private(set) var estimatedFeeLamports: UInt64 = 5100

    /// Estimated fee in SOL (convenience accessor).
    var estimatedFeeSOL: Decimal { Decimal(estimatedFeeLamports) / Decimal(1_000_000_000) }

    /// Live network congestion: recent median prioritization fee in micro-lamports
    /// per compute unit (0 = idle/unknown). Drives the Home gas tracker.
    private(set) var networkPriorityMicroLamports: Double = 0
    /// A realistic total fee for a typical app tx at the current network rate:
    /// base 5000 + our priority price applied over ~200k compute units.
    var liveFeeLamports: UInt64 {
        let rate = max(Double(MemoTransactionBuilder.computeUnitPriceMicroLamports), networkPriorityMicroLamports)
        return 5000 + UInt64(rate * 200_000 / 1_000_000)
    }
    var liveFeeSOL: Decimal { Decimal(liveFeeLamports) / Decimal(1_000_000_000) }

    /// Fetch the recent median prioritization fee (getRecentPrioritizationFees).
    func refreshNetworkFee() async {
        guard let url = URL(string: currentEndpoint.address) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "getRecentPrioritizationFees", "params": [[String]()]
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]], !result.isEmpty else { return }
        let fees = result.compactMap { ($0["prioritizationFee"] as? NSNumber)?.doubleValue }.sorted()
        guard !fees.isEmpty else { return }
        networkPriorityMicroLamports = fees[fees.count / 2]   // median
    }

    init() {
        let eps = Self.buildEndpoints()
        endpoints = eps
        client = JSONRPCAPIClient(endpoint: eps[0])
    }

    /// Rotate to the next endpoint after a failure.
    func rotate() {
        currentIndex = (currentIndex + 1) % endpoints.count
        client = JSONRPCAPIClient(endpoint: endpoints[currentIndex])
    }

    /// Set (or clear with nil/empty) the user's custom RPC and rebuild the pool.
    /// Returns false if the URL is invalid.
    @discardableResult
    func setCustomRPC(_ urlString: String?) -> Bool {
        let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.customKey)
        } else {
            guard let url = URL(string: trimmed), url.scheme == "https" else { return false }
            UserDefaults.standard.set(trimmed, forKey: Self.customKey)
        }
        endpoints = Self.buildEndpoints()
        currentIndex = 0
        client = JSONRPCAPIClient(endpoint: endpoints[0])
        return true
    }

    /// Refresh the estimated network fee.
    /// Solana's base fee is 5000 lamports per signature (protocol constant since genesis).
    /// Our memo transactions always have exactly 1 signer, so the fee is always 5000 lamports.
    func refreshFee(senderKeyPair: KeyPair) async {
        estimatedFeeLamports = 5100
    }
}
