//
//  Curve25519PublicKey.swift
//  
//
//  Created by Volkov Alexander on 5/3/20.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
import CCurve25519

public struct Curve25519PublicKey {
    
    public var key: Any!
    
    /// A data representation of the private key
    public var rawRepresentation: Data {
        if #available(iOS 13.0, *) {
            if let key = key as? Curve25519.Signing.PublicKey {
                return key.rawRepresentation
            }
        }
        return key as! Data
    }
    
    @available(iOS 13.0, *)
    public init(publicKey: Curve25519.Signing.PublicKey) {
        key = publicKey
    }
    
    public init<D>(rawRepresentation: D) throws where D : ContiguousBytes {
        if #available(iOS 13.0, *) {
            key = try Curve25519.Signing.PublicKey(rawRepresentation: rawRepresentation)
            return
        }
        key = rawRepresentation
    }
    
    /// Verifies an EdDSA signature over Curve25519.
    ///
    /// - Parameters:
    ///   - signature: The 64-bytes signature to verify.
    ///   - data: The digest that was signed.
    /// - Returns: True if the signature is valid. False otherwise.
    public func isValidSignature<S, D>(_ signature: S, for data: D) -> Bool where S : DataProtocol, D : DataProtocol {
        if #available(iOS 13.0, *) {
            if let key = key as? Curve25519.Signing.PublicKey {
                return key.isValidSignature(signature, for: data)
            }
        }
        return Curve25519PublicKey.verify(signature: signature as! Data, for: data as! Data, publicKey: key as! Data)
    }
    
    public static func verify(signature: Data, for message: Data, publicKey: Data) -> Bool {
        guard signature.count == Curve25519KeyLength.signature,
            publicKey.count == Curve25519KeyLength.key else {
                return false
        }
        guard message.count > 0 else {
            return false
        }
        let result: Int32 = signature.withUnsafeBytes { sigPtr in
            publicKey.withUnsafeBytes { keyPtr in
                message.withUnsafeBytes { msgPtr in
                    curve25519_verify(sigPtr, keyPtr, msgPtr, UInt(message.count))
                }
            }
        }
        return result == 0
    }
}
