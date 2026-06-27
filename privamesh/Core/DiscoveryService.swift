//
//  DiscoveryService.swift
//  privamesh
//
//  Handles user discovery: publish own bundle on setup,
//  search for contacts by nickname or Solana address.
//
//  API base: https://discovery.privamesh.io/v1
//  POST /register  { address, bundle }
//  GET  /search?q= → { address, nickname, bundle }
//

import Foundation

@Observable
final class DiscoveryService {
    private static let baseURL = "https://discovery.privamesh.io/v1"

    struct DiscoveryUser {
        let address: String
        let nickname: String      // auto-generated from address
        let bundleBase64: String
        var avatarSeed: String? = nil   // the user's equipped NFT avatar, if any
    }

    enum DiscoveryError: LocalizedError {
        case notFound
        case networkError
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notFound:         return "Пользователь не найден"
            case .networkError:     return "Ошибка сети — проверь соединение"
            case .invalidResponse:  return "Неожиданный ответ сервера"
            }
        }
    }

    // MARK: - Search

    func search(query: String) async throws -> DiscoveryUser {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DiscoveryError.networkError }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "\(Self.baseURL)/search?q=\(encoded)") else {
            throw DiscoveryError.networkError
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw DiscoveryError.networkError
        }

        guard let http = response as? HTTPURLResponse else { throw DiscoveryError.networkError }

        if http.statusCode == 404 { throw DiscoveryError.notFound }
        guard http.statusCode == 200 else { throw DiscoveryError.networkError }

        guard let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            throw DiscoveryError.invalidResponse
        }

        return DiscoveryUser(
            address: decoded.address,
            nickname: decoded.nickname,
            bundleBase64: decoded.bundle
        )
    }

    // MARK: - Register

    func register(address: String, bundleBase64: String) async {
        guard let url = URL(string: "\(Self.baseURL)/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = RegisterRequest(address: address, bundle: bundleBase64)
        guard let encoded = try? JSONEncoder().encode(body) else { return }
        request.httpBody = encoded

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Codable models

    private struct SearchResponse: Decodable {
        let address: String
        let nickname: String
        let bundle: String
    }

    private struct RegisterRequest: Encodable {
        let address: String
        let bundle: String
    }
}
