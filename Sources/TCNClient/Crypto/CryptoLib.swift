//
//  Created by Eugene Kolpakov on 2020-04-25.
//

import Foundation
import CryptoKit
import CommonCrypto
import ed25519swift

@available(iOS 13.0, *)
extension SHA256.Digest: DataRepresentable {}

/// Generic interface for working with asymmetric keys
public protocol AsymmetricKeyPair {

    var privateKey: Data { get }
    var publicKey: Data { get }

    func signature(for data: Data) throws -> Data
}


class CryptoLib {

    static func generateKeyPair() -> AsymmetricKeyPair {
        if #available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *) {
            return CryptoKitEllipticCurveKeyPair()
        } else {
            return Ed25519LibEllipticCurveKeyPair()
        }
    }

    static func restoreKeyPair(serializedSecret: Data) throws -> AsymmetricKeyPair {
        if #available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *) {
            return try CryptoKitEllipticCurveKeyPair(rawRepresentation: serializedSecret)
        } else {
            return try Ed25519LibEllipticCurveKeyPair(rawRepresentation: serializedSecret)
        }
    }

    static func isValidSignature(_ signature: Data, for data: Data, key: Data) throws -> Bool {
        if #available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *) {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
            return publicKey.isValidSignature(signature, for: data)
        } else {
            return Ed25519.verify(signature: signature.bytes, message: data.bytes, publicKey: key.bytes)
        }
    }

    static func sha256(data : Data) -> Data {
        if #available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *) {
            return SHA256.hash(data: data).dataRepresentation
        } else {
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes {
                _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
            }
            return Data(hash)
        }
    }
}

/// Uses CryptoKit APIs for working with asymmetric keys on OS versions that support CryptoKit.
@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
fileprivate struct CryptoKitEllipticCurveKeyPair: AsymmetricKeyPair {

    private let curve25519PrivateKey: Curve25519.Signing.PrivateKey

    var privateKey: Data { return curve25519PrivateKey.rawRepresentation }
    var publicKey: Data { return curve25519PrivateKey.publicKey.rawRepresentation }

    init() {
        curve25519PrivateKey = Curve25519.Signing.PrivateKey()
    }

    init(rawRepresentation: Data) throws {
        curve25519PrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    func signature(for data: Data) throws -> Data {
        return try curve25519PrivateKey.signature(for: data)
    }
}

/// Uses `ed25519swift` open-source library for working with asymmetric keys on OS versions that don't support CryptoKit.
fileprivate struct Ed25519LibEllipticCurveKeyPair: AsymmetricKeyPair {

    let privateKey: Data
    let publicKey: Data

    init() {
        let (publicKeyBytes, privateKeyBytes) = Ed25519.generateKeyPair()
        privateKey = Data(privateKeyBytes)
        publicKey = Data(publicKeyBytes)
    }

    init(rawRepresentation: Data) throws {
        privateKey = rawRepresentation
        publicKey = Data(Ed25519.calcPublicKey(secretKey: rawRepresentation.bytes))
    }

    func signature(for data: Data) throws -> Data {
        return Data(Ed25519.sign(message: data.bytes, secretKey: privateKey.bytes))
    }
}
