//
//  Curve25519PrivateKey.swift
//  
//
//  Created by Volkov Alexander on 5/3/20.
//

import Foundation
//import CryptoKit
import CCurve25519

public struct Curve25519KeyLength {

    /// The length of the private and public key in bytes
    public static let key = 32

    /// The length of a signature in bytes
    public static let signature = 64

    /// The number of random bytes needed for signing
    public static let random = 64

    /// The default basepoint for X25519 key agreement
    public static let basepoint: Data = [9] + Data(repeating: 0, count: 31)

    // MARK: VRF Constants
    /// The length of a VRF signature in bytes
    public static let vrfSignature = 96

    /// The number of random bytes needed for signing
    public static let vrfRandom = 32

    /// The length of the VRF verification output in bytes
    public static let vrfVerify = 32
}

public struct Curve25519PrivateKey {
    
    public let key: Any!
    
    /// The associated public key for verifying signatures done with this private key.
    ///
    /// - Returns: The associated public key
    public var publicKey: Curve25519PublicKey!
    
    public var privateKey: Data!
    
    /// Generates a Curve25519 Signing Key.
    public init() {
//        if #available(iOS 13.2, *) {
//            self.key = Curve25519.Signing.PrivateKey()
//        } else {
            self.key = Curve25519PrivateKey.generateRandomData(count: Curve25519KeyLength.key)!
//        }
        try! initPublicKey()
    }
    
    public init<D>(rawRepresentation data: D) throws where D : ContiguousBytes {
//        if #available(iOS 13.2, *) {
//            self.key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
//        }
//        else {
            self.key = data
//        }
        try initPublicKey()
    }
    
    // Initialize related public key
    private mutating func initPublicKey() throws {
//        if #available(iOS 13.2, *) {
//            if let key = key as? Curve25519.Signing.PrivateKey {
//                publicKey = Curve25519PublicKey(publicKey: key.publicKey)
//                return
//            }
//        }
        let (priv, pub) = try Curve25519PrivateKey.generatePublicKey(bytes: key as! Data)
        publicKey = try Curve25519PublicKey(rawRepresentation: pub)
        privateKey = priv
    }
    
    /// A data representation of the private key
    public var rawRepresentation: Data {
//        if #available(iOS 13.2, *) {
//            if let key = key as? Curve25519.Signing.PrivateKey {
//                return key.rawRepresentation
//            }
//        }
        return key as! Data
    }
    
    /// Generates an EdDSA signature over Curve25519.
    ///
    /// - Parameter data: The data to sign.
    /// - Returns: The 64-bytes signature.
    /// - Throws: If there is a failure producing the signature.
    public func signature<D>(for data: D) throws -> Data where D : DataProtocol {
//        if #available(iOS 13.2, *) {
//            if let key = key as? Curve25519.Signing.PrivateKey {
//                return try key.signature(for: data)
//            }
//        }
        return try Curve25519PrivateKey.signature(for: data as! Data, privateKey: privateKey, randomData: Curve25519PrivateKey.generateRandomData(count: Curve25519KeyLength.random)!)
    }
    
    /// Generate random private key
    public static func generateRandomData(count: Int) -> Data? {
        
        var keyData = Data(count: count)
        let result = keyData.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Curve25519KeyLength.key, $0.baseAddress!)
        }
        if result == errSecSuccess {
            return keyData
        } else {
            print("Problem generating random bytes")
            return nil
        }
    }
    
    public static func generatePublicKey(bytes: Data, basepoint: Data = Curve25519KeyLength.basepoint) throws -> (Data, Data) {
        var privateKey: Data = Data(count: Curve25519KeyLength.key)
        guard privateKey.count == Curve25519KeyLength.key else { throw "Incorrect private key length: \(privateKey.count)" }
        guard basepoint.count == Curve25519KeyLength.key else { throw "Incorrect basepoint length: \(privateKey.count)" }
        
        var pubKey = Data(count: Curve25519KeyLength.key)
        let result: Int32 = pubKey.withUnsafeMutableBytes { (pubKeyPtr: UnsafeMutablePointer<UInt8>) in
            privateKey.withUnsafeMutableBytes { (privPtr: UnsafeMutablePointer<UInt8>) in
                privPtr[0] &= 248 // clear lowest bit
                privPtr[31] &= 63 // clear highest bit
                privPtr[31] |= 64 // set second highest bit
                return basepoint.withUnsafeBytes { basepointPtr in
                    curve25519_donna(pubKeyPtr, privPtr, basepointPtr)
                }
            }
        }
//        let result: Int32 = data.withUnsafeMutableBytes { keyPtrBytes in
//            if let keyPtr = keyPtrBytes.bindMemory(to: UInt8.self).baseAddress {
//                privateKey.withUnsafeBytes { privPtrBytes in
//                    if let privPtr = privPtrBytes.bindMemory(to: UInt8.self).baseAddress {
//                        basepoint.withUnsafeBytes { basepointPtrBytes in
//                            if let basepointPtr = basepointPtrBytes.bindMemory(to: UInt8.self).baseAddress {
//                                curve25519_donna(keyPtr, privPtr, basepointPtr)
//                            }
//                        }
//                    }
//                }
//            }
//        }
        
        guard result == 0 else {
            throw "Incorrect result \(result)"
        }
        return (privateKey, pubKey)
    }
    
    public static func signature(for message: Data, privateKey: Data, randomData: Data) throws -> Data {
        let length = message.count
        guard length > 0 else { throw "Incorrect message length: \(length)" }
        guard randomData.count == Curve25519KeyLength.random else { throw "Incorrect private key length: \(randomData.count)" }
        guard privateKey.count == Curve25519KeyLength.key else { throw "Incorrect private key length: \(privateKey.count)" }
        
        var signature = Data(count: Curve25519KeyLength.signature)
        let result: Int32 = randomData.withUnsafeBytes{ randomPtr in
            signature.withUnsafeMutableBytes { sigPtr in
                privateKey.withUnsafeBytes{ keyPtr in
                    message.withUnsafeBytes { messPtr in
                        curve25519_sign(sigPtr, keyPtr, messPtr, UInt(length), randomPtr)
                    }
                }
            }
        }
//        let result: Int32 = randomData.withUnsafeBytes{ randomPtrBytes in
//            if let randomPtr = randomPtrBytes.bindMemory(to: UInt8.self).baseAddress {
//                signature.withUnsafeMutableBytes { sigPtrBytes in
//                    if let sigPtr = sigPtrBytes.bindMemory(to: UInt8.self).baseAddress {
//                        privateKey.withUnsafeBytes{ keyPtrBytes in
//                            if let keyPtr = keyPtrBytes.bindMemory(to: UInt8.self).baseAddress {
//                                message.withUnsafeBytes { messPtrBytes in
//                                    if let messPtr = messPtrBytes.bindMemory(to: UInt8.self).baseAddress {
//                                        curve25519_sign(sigPtr, keyPtr, messPtr, UInt(length), randomPtr)
//                                    }
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//        }
        guard result == 0 else {
            throw "Incorrect result \(result)"
        }
        return signature
    }
}

extension String: Error {}
