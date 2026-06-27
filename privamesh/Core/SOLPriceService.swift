//
//  SOLPriceService.swift
//  privamesh
//

import Foundation

@Observable
final class SOLPriceService {
    private(set) var priceUSD: Double?
    private(set) var change24h: Double?
    private var lastFetch: Date?

    func refresh() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < 300 { return }
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd&include_24hr_change=true") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(CoinGeckoResponse.self, from: data)
            await MainActor.run {
                priceUSD = resp.solana?.usd
                change24h = resp.solana?.usd_24h_change
                lastFetch = Date()
            }
        } catch {}
    }

    func usdValue(sol: Decimal) -> Double? {
        guard let price = priceUSD else { return nil }
        return (sol as NSDecimalNumber).doubleValue * price
    }

    // MARK: - Historical price (USD on a given date)

    private var historyCache: [String: Double] = [:]

    /// SOL→USD price on `date` (CoinGecko daily). Cached per day; falls back to
    /// the current price if the lookup fails.
    @MainActor
    func historicalUSD(on date: Date) async -> Double? {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd-MM-yyyy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let key = fmt.string(from: date)
        if let cached = historyCache[key] { return cached }

        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/solana/history?date=\(key)&localization=false"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let md   = json["market_data"] as? [String: Any],
              let cp   = md["current_price"] as? [String: Any],
              let usd  = cp["usd"] as? Double
        else { return priceUSD }   // fallback to current
        historyCache[key] = usd
        return usd
    }
}

private struct CoinGeckoResponse: Decodable {
    let solana: SolanaPrice?
    struct SolanaPrice: Decodable {
        let usd: Double
        let usd_24h_change: Double
    }
}
