//
//  Created by Zsombor Szabo on 03/04/2020.
//  

import Foundation
import CryptoKit

extension SHA256.Digest: DataRepresentable {}
extension UInt8: DataRepresentable {}
extension UInt16: DataRepresentable {}
extension MemoType: DataRepresentable {}

public let H_TCK_DOMAIN_SEPARATOR = "H_TCK".data(using: .utf8)!
public let H_TCN_DOMAIN_SEPARATOR = "H_TCN".data(using: .utf8)!

/// Authorizes publication of a report of potential exposure.
public struct ReportAuthorizationKey: Equatable {
    
    /// Initialize a new report authorization key from a random number generator.
    public var reportAuthorizationPrivateKey = Curve25519.Signing.PrivateKey()
    
    /// Compute the initial temporary contact key derived from this report authorization key.
    ///
    /// Note: this returns `tck_1`, the first temporary contact key that can be used to generate tcks.
    public var initialTemporaryContactKey: TemporaryContactKey {
        return self.tck_0.ratchet()! // It's safe to unwrap.
    }
    
    /// This is internal because tck_0 shouldn't be used to generate a TCN.
    var tck_0: TemporaryContactKey {
        return TemporaryContactKey(
            index: 0,
            reportVerificationPublicKeyBytes: reportAuthorizationPrivateKey
                .publicKey.rawRepresentation,
            bytes: SHA256.hash(data: H_TCK_DOMAIN_SEPARATOR + reportAuthorizationPrivateKey.rawRepresentation).dataRepresentation
        )
    }
    
    public init(
        reportAuthorizationPrivateKey: Curve25519.Signing.PrivateKey = .init()
    ) {
        self.reportAuthorizationPrivateKey = reportAuthorizationPrivateKey
    }
    
    public static func == (
        lhs: ReportAuthorizationKey,
        rhs: ReportAuthorizationKey
    ) -> Bool {
        return lhs.reportAuthorizationPrivateKey.rawRepresentation == rhs.reportAuthorizationPrivateKey.rawRepresentation
    }
    
}

/// A pseudorandom 128-bit value broadcast to nearby devices over Bluetooth.
public struct TemporaryContactNumber: Equatable {
    
    /// The 16 bytes of the temporary contact number.
    public var bytes: Data
    
    public init(bytes: Data) {
        self.bytes = bytes
    }
    
}

/// A ratcheting key used to derive temporary contact numbers.
public struct TemporaryContactKey: Equatable {
    
    /// The current ratchet index.
    public var index: UInt16
    
    /// The 32 bytes of the ed25519 public key used for report verification.
    public var reportVerificationPublicKeyBytes: Data
    
    /// The 32 bytes of the temporary contact key.
    public var bytes: Data
    
    /// Compute the temporary contact number derived from this key.
    public var temporaryContactNumber: TemporaryContactNumber {
        return TemporaryContactNumber(
            bytes: SHA256.hash(
                data: H_TCN_DOMAIN_SEPARATOR + index.dataRepresentation + bytes
            ).dataRepresentation[0..<16]
        )
    }
    
    public init(
        index: UInt16, reportVerificationPublicKeyBytes: Data,
        bytes: Data
    ) {
        self.index = index
        self.reportVerificationPublicKeyBytes = reportVerificationPublicKeyBytes
        self.bytes = bytes
    }
    
    /// Ratchet the key forward, producing a new key for a new temporary contact number.
    /// - Returns: A new temporary contact key if `index` is less than `UInt16.max`, nil
    ///     otherwise, signaling that the report authorization key should be rotated.
    public func ratchet() -> TemporaryContactKey? {
        guard index < .max else {
            return nil
        }
        
        let nextBytes = SHA256.hash(
            data: H_TCK_DOMAIN_SEPARATOR + reportVerificationPublicKeyBytes + bytes
        ).dataRepresentation
        
        return TemporaryContactKey(
            index: index + 1,
            reportVerificationPublicKeyBytes: reportVerificationPublicKeyBytes,
            bytes: nextBytes
        )
    }    
    
}
