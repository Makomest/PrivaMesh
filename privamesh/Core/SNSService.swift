//
//  SNSService.swift
//  privamesh
//
//  Solana Name Service (SNS) lookup via Bonfida REST proxy.
//  Resolves .sol domain ↔ wallet address.
//

import Foundation

enum SNSError: LocalizedError {
    case networkError
    case notFound
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .networkError:     return "Network error during SNS lookup"
        case .notFound:         return "Domain not found"
        case .invalidResponse:  return "Invalid SNS response"
        }
    }
}

@Observable
final class SNSService {
    private static let baseURL = "https://sns-sdk-proxy.bonfida.workers.dev"

    // Simple in-memory cache: address → domain, domain → address
    private var domainCache: [String: String] = [:]

    // MARK: - Resolve domain → address

    func resolve(domain: String) async throws -> String {
        let key = "d:\(domain)"
        if let cached = domainCache[key] { return cached }

        let clean = domain.hasSuffix(".sol") ? String(domain.dropLast(4)) : domain
        guard let url = URL(string: "\(Self.baseURL)/resolve/\(clean)") else {
            throw SNSError.networkError
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONDecoder().decode(SNSResolveResponse.self, from: data) else {
            throw SNSError.invalidResponse
        }
        if let address = json.result {
            domainCache[key] = address
            domainCache["a:\(address)"] = domain
            return address
        }
        throw SNSError.notFound
    }

    // MARK: - Reverse lookup: address → domain

    func lookup(address: String) async -> String? {
        let key = "a:\(address)"
        if let cached = domainCache[key] { return cached }

        guard let url = URL(string: "\(Self.baseURL)/domain/\(address)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONDecoder().decode(SNSDomainResponse.self, from: data),
              let domain = json.result?.first else { return nil }

        let fullDomain = domain + ".sol"
        domainCache[key] = fullDomain
        domainCache["d:\(domain)"] = address
        return fullDomain
    }
}

// MARK: - Response models

private struct SNSResolveResponse: Decodable { let result: String? }
private struct SNSDomainResponse: Decodable { let result: [String]? }
