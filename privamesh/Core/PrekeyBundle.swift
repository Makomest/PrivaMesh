//
//  PrekeyBundle.swift
//  privamesh
//
//  X3DH prekey bundle — exchanged via QR code between contacts.
//  Computes the initial shared secret for the Double Ratchet session.
//

import Foundation
import CryptoKit
import SolanaSwift
import TweetNacl

// MARK: - PrekeyBundle

/// Public bundle published by each user. Shared via QR code or on-chain memo.
struct PrekeyBundle: Codable {
    /// Curve25519 KeyAgreement public key — used for X3DH DH operations.
    let dhIdentityKey: Data          // 32 bytes

    /// Short-term signed prekey — Curve25519 KeyAgreement public key.
    let signedPrekeyPublic: Data     // 32 bytes

    /// Ed25519 signature of signedPrekeyPublic, produced by the signing identity key.
    let signedPrekeySignature: Data  // 64 bytes

    /// Optional one-time prekey — consumed on first session establishment.
    let oneTimePrekeyPublic: Data?   // 32 bytes

    /// Curve25519 Signing public key — used only to verify the SPK signature.
    let signingIdentityKey: Data     // 32 bytes

    /// The Solana wallet address that published this bundle (optional, legacy nil).
    var walletAddress: String? = nil
    /// Ed25519 signature over `canonicalBytes` by the wallet key — proves the
    /// bundle belongs to `walletAddress`, blocking discovery-server impersonation.
    var walletSignature: Data? = nil

    /// Verify the signed-prekey signature. Throws CryptoError.invalidSignature on failure.
    func verify() throws {
        let sigKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingIdentityKey)
        guard sigKey.isValidSignature(signedPrekeySignature, for: signedPrekeyPublic) else {
            throw CryptoError.invalidSignature
        }
    }

    // MARK: - Wallet binding (anti-MITM)

    /// Crypto material the wallet signs — order-fixed, excludes the wallet fields.
    var canonicalBytes: Data {
        var d = Data()
        d.append(dhIdentityKey)
        d.append(signedPrekeyPublic)
        d.append(signedPrekeySignature)
        if let opk = oneTimePrekeyPublic { d.append(opk) }
        d.append(signingIdentityKey)
        return d
    }

    /// A copy cryptographically bound to `address` via the wallet key.
    func walletSigned(address: String, keypair: KeyPair) -> PrekeyBundle {
        var copy = self
        copy.walletAddress = address
        copy.walletSignature = try? NaclSign.signDetached(
            message: canonicalBytes, secretKey: keypair.secretKey)
        return copy
    }

    /// True iff a valid wallet signature binds this bundle to `address`.
    func isBoundTo(address: String) -> Bool {
        guard let sig = walletSignature, walletAddress == address,
              let pub = try? PublicKey(string: address), pub.bytes.count == PublicKey.numberOfBytes
        else { return false }
        return (try? NaclSign.signDetachedVerify(message: canonicalBytes, sig: sig, publicKey: pub.data)) ?? false
    }

    // MARK: Serialization for QR / on-chain

    var base64Encoded: String {
        (try? Data(JSONEncoder().encode(self)).base64EncodedString()) ?? ""
    }

    static func fromBase64(_ string: String) throws -> PrekeyBundle {
        guard let data = Data(base64Encoded: string) else { throw CryptoError.invalidData }
        return try JSONDecoder().decode(PrekeyBundle.self, from: data)
    }

}

// MARK: - Compact packing (on-chain discovery — base64(JSON) is too big for a memo)

extension PrekeyBundle {
    /// Tightly packed binary form (~289 B vs ~800 chars for base64(JSON)), so the
    /// whole discovery record fits inside one memo transaction.
    /// Layout: [flags:1][dhIdentityKey:32][signingIdentityKey:32]
    ///         [signedPrekeyPublic:32][signedPrekeySignature:64]
    ///         (+[oneTimePrekeyPublic:32] if flags bit0)
    ///         (+[walletAddress:32][walletSignature:64] if flags bit1)
    var discoveryPacked: Data {
        var d = Data()
        let walletBytes = walletAddress.flatMap { try? PublicKey(string: $0).data }
        var flags: UInt8 = 0
        if oneTimePrekeyPublic != nil { flags |= 1 }
        if walletBytes != nil, walletSignature != nil { flags |= 2 }
        d.append(flags)
        d.append(dhIdentityKey)
        d.append(signingIdentityKey)
        d.append(signedPrekeyPublic)
        d.append(signedPrekeySignature)
        if let opk = oneTimePrekeyPublic { d.append(opk) }
        if flags & 2 != 0, let wb = walletBytes, let ws = walletSignature { d.append(wb); d.append(ws) }
        return d
    }

    init?(discoveryPacked d: Data) {
        var off = 0
        func take(_ n: Int) -> Data? {
            guard d.count - off >= n else { return nil }
            let r = d.subdata(in: d.index(d.startIndex, offsetBy: off)..<d.index(d.startIndex, offsetBy: off + n))
            off += n
            return r
        }
        guard let flags = take(1)?.first,
              let dh = take(32), let sik = take(32), let spk = take(32), let sig = take(64)
        else { return nil }
        var opk: Data? = nil
        if flags & 1 != 0 { guard let o = take(32) else { return nil }; opk = o }
        var addr: String? = nil
        var wsig: Data? = nil
        if flags & 2 != 0 {
            guard let wb = take(64 + 32) else { return nil }
            addr = (try? PublicKey(data: Data(wb.prefix(32))))?.base58EncodedString
            wsig = Data(wb.suffix(64))
            if addr == nil { return nil }
        }
        self.init(
            dhIdentityKey: dh,
            signedPrekeyPublic: spk,
            signedPrekeySignature: sig,
            oneTimePrekeyPublic: opk,
            signingIdentityKey: sik,
            walletAddress: addr,
            walletSignature: wsig)
    }
}

// MARK: - CryptoIdentity

/// Per-device messaging identity — stored in Keychain, independent of Solana wallet key.
struct CryptoIdentity: Codable {
    let dhIdentityKeyData: Data       // Curve25519.KeyAgreement private key (32 bytes)
    let signingKeyData: Data          // Curve25519.Signing private key (32 bytes)
    let signedPrekeyData: Data        // Curve25519.KeyAgreement private key (32 bytes)
    let signedPrekeySignature: Data   // 64 bytes

    static func generate() throws -> CryptoIdentity {
        let dhIK  = Curve25519.KeyAgreement.PrivateKey()
        let sigIK = Curve25519.Signing.PrivateKey()
        let spk   = Curve25519.KeyAgreement.PrivateKey()
        let sig   = try sigIK.signature(for: spk.publicKey.rawRepresentation)
        return CryptoIdentity(
            dhIdentityKeyData: dhIK.rawRepresentation,
            signingKeyData: sigIK.rawRepresentation,
            signedPrekeyData: spk.rawRepresentation,
            signedPrekeySignature: Data(sig)
        )
    }

    /// Deterministically derive the messaging identity from the wallet's BIP39
    /// seed phrase via HKDF-SHA256. The same phrase always yields the same keys,
    /// so the identity (and thus the account's provable presence to contacts) is
    /// recoverable on any device just by re-entering the phrase — no server, no
    /// extra backup. Distinct `info` labels give per-purpose domain separation,
    /// and a messaging-specific salt keeps these keys unrelated to the Solana
    /// wallet key derived from the same phrase. Ed25519 signatures are
    /// deterministic (RFC 8032), so the produced bundle is byte-identical across
    /// derivations of the same phrase.
    static func derive(fromSeedPhrase words: [String]) throws -> CryptoIdentity {
        let normalized = words.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let ikm  = Data(normalized.utf8)
        let salt = Data("PrivaMesh-msg-identity-v1".utf8)
        func sk(_ label: String) -> Data {
            CryptoBox.hkdf(inputKeyMaterial: ikm, salt: salt,
                           info: Data(label.utf8), outputByteCount: 32)
        }
        let dhIK  = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: sk("dhIdentityKey"))
        let sigIK = try Curve25519.Signing.PrivateKey(rawRepresentation: sk("signingKey"))
        let spk   = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: sk("signedPrekey"))
        let sig   = try sigIK.signature(for: spk.publicKey.rawRepresentation)
        return CryptoIdentity(
            dhIdentityKeyData: dhIK.rawRepresentation,
            signingKeyData: sigIK.rawRepresentation,
            signedPrekeyData: spk.rawRepresentation,
            signedPrekeySignature: Data(sig)
        )
    }

    func dhIdentityKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try .init(rawRepresentation: dhIdentityKeyData)
    }

    func signedPrekey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try .init(rawRepresentation: signedPrekeyData)
    }

    func prekeyBundle() throws -> PrekeyBundle {
        let dhIK  = try dhIdentityKey()
        let spk   = try signedPrekey()
        let sigIK = try Curve25519.Signing.PrivateKey(rawRepresentation: signingKeyData)
        return PrekeyBundle(
            dhIdentityKey: dhIK.publicKey.rawRepresentation,
            signedPrekeyPublic: spk.publicKey.rawRepresentation,
            signedPrekeySignature: signedPrekeySignature,
            oneTimePrekeyPublic: nil,
            signingIdentityKey: sigIK.publicKey.rawRepresentation
        )
    }
}

// MARK: - X3DH

/// Extended Triple Diffie-Hellman — computes the initial shared secret for a DR session.
enum X3DH {
    private static let info = Data("PrivaMesh-X3DH-v1".utf8)
    private static let salt = Data(repeating: 0x00, count: 32)

    /// Alice computes SK using Bob's prekey bundle and her ephemeral key.
    static func senderSharedSecret(
        myIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        myEphemeralKey: Curve25519.KeyAgreement.PrivateKey,
        remoteBundle: PrekeyBundle
    ) throws -> Data {
        try remoteBundle.verify()

        let ikB  = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteBundle.dhIdentityKey)
        let spkB = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteBundle.signedPrekeyPublic)

        var ikm  = try CryptoBox.dh(privateKey: myIdentityKey,  publicKey: spkB) // DH(IK_A, SPK_B)
        ikm     += try CryptoBox.dh(privateKey: myEphemeralKey, publicKey: ikB)  // DH(EK_A, IK_B)
        ikm     += try CryptoBox.dh(privateKey: myEphemeralKey, publicKey: spkB) // DH(EK_A, SPK_B)

        if let opkRaw = remoteBundle.oneTimePrekeyPublic {
            let opkB = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: opkRaw)
            ikm += try CryptoBox.dh(privateKey: myEphemeralKey, publicKey: opkB)  // DH(EK_A, OPK_B)
        }

        return CryptoBox.hkdf(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: 32)
    }

    /// Bob computes the same SK from his private keys and Alice's public keys.
    static func receiverSharedSecret(
        myIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        mySignedPrekey: Curve25519.KeyAgreement.PrivateKey,
        myOneTimePrekey: Curve25519.KeyAgreement.PrivateKey? = nil,
        senderIdentityKeyPublic: Data,
        senderEphemeralKeyPublic: Data
    ) throws -> Data {
        let ikA = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderIdentityKeyPublic)
        let ekA = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderEphemeralKeyPublic)

        var ikm  = try CryptoBox.dh(privateKey: mySignedPrekey, publicKey: ikA)  // DH(SPK_B, IK_A)
        ikm     += try CryptoBox.dh(privateKey: myIdentityKey,  publicKey: ekA)  // DH(IK_B, EK_A)
        ikm     += try CryptoBox.dh(privateKey: mySignedPrekey, publicKey: ekA)  // DH(SPK_B, EK_A)

        if let opk = myOneTimePrekey {
            ikm += try CryptoBox.dh(privateKey: opk, publicKey: ekA)             // DH(OPK_B, EK_A)
        }

        return CryptoBox.hkdf(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: 32)
    }
}
