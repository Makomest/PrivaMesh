//
//  IrysUploader.swift
//  privamesh
//
//  Uploads encrypted data to Arweave via the Irys network.
//  Implements ANS-104 Data Item format (Solana Ed25519 signing).
//  Uploads < 100 KB are free — no wallet funding required.
//

import Foundation
import CryptoKit
import SolanaSwift
import TweetNacl

enum IrysError: LocalizedError {
    case serverError(statusCode: Int, message: String)
    case downloadFailed
    case invalidTxId

    var errorDescription: String? {
        switch self {
        case .serverError(let code, let msg): return "Irys error \(code): \(msg)"
        case .downloadFailed: return "Could not download photo from Arweave"
        case .invalidTxId:    return "Invalid Arweave transaction ID"
        }
    }
}

enum IrysUploader {
    private static let uploadURL      = URL(string: "https://uploader.irys.xyz/upload/solana")!
    private static let arweaveGateway = "https://arweave.net/"

    private struct UploadResponse: Decodable { let id: String }

    // MARK: - Upload / Download

    static func upload(_ data: Data, keypair: KeyPair) async throws -> String {
        let item = try makeDataItem(data: data, keypair: keypair)
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = item
        let (responseData, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw IrysError.serverError(statusCode: http.statusCode, message: body)
        }
        return try JSONDecoder().decode(UploadResponse.self, from: responseData).id
    }

    static func download(txId: String) async throws -> Data {
        guard let url = URL(string: arweaveGateway + txId) else { throw IrysError.invalidTxId }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw IrysError.downloadFailed
        }
        return data
    }

    // MARK: - ANS-104 Data Item (Solana Ed25519, sig_type = 2)

    private static func makeDataItem(data: Data, keypair: KeyPair) throws -> Data {
        let sigType: UInt16 = 2
        let owner = keypair.publicKey.data  // 32 bytes

        var anchor = Data(count: 32)
        anchor.withUnsafeMutableBytes { buf in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, buf.baseAddress!)
        }

        let sigTypeBytes = Data([UInt8(sigType & 0xFF), UInt8(sigType >> 8)])

        // Build deep-hash input list
        let toSign: [Data] = [
            Data("dataitem".utf8),
            Data("1".utf8),
            sigTypeBytes,
            owner,
            Data(),    // no target
            anchor,
            Data(),    // no tags (empty Avro)
            data
        ]
        let hashResult = deepHash(toSign)
        let signature = try NaclSign.signDetached(message: hashResult, secretKey: keypair.secretKey)

        // Assemble binary bundle item
        var item = Data()
        item.append(sigTypeBytes)
        item.append(signature)   // 64 bytes
        item.append(owner)       // 32 bytes
        item.append(0)           // target present = false
        item.append(1)           // anchor present = true
        item.append(anchor)      // 32 bytes
        item.append(contentsOf: [UInt8](repeating: 0, count: 8))  // num_tags = 0
        item.append(contentsOf: [UInt8](repeating: 0, count: 8))  // num_tags_bytes = 0
        item.append(data)
        return item
    }

    // MARK: - deepHash (SHA-384 based, per Arweave spec)

    private static func deepHashChunk(_ data: Data) -> Data {
        let tag = Data("blob\(data.count)".utf8)
        return Data(SHA384.hash(data: tag + data))
    }

    private static func deepHash(_ chunks: [Data]) -> Data {
        let tag = Data("list\(chunks.count)".utf8)
        var acc = Data(SHA384.hash(data: tag))
        for chunk in chunks {
            acc = Data(SHA384.hash(data: acc + deepHashChunk(chunk)))
        }
        return acc
    }
}
