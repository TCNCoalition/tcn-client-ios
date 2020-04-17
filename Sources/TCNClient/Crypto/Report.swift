//
//  Created by Zsombor Szabo on 03/04/2020.
//  

import Foundation

//import CryptoKit
import CryptoKit25519

/// Describes the intended type of the contents of a memo field.
public enum MemoType: UInt8 {
    /// The CoEpi symptom self-report format, version 1 (TBD).
    case CoEpiV1 = 0
    /// The CovidWatch test data format, version 1 (TBD).
    case CovidWatchV1 = 1
    /// Reserved for future use.
    case Reserved = 0xFF
}

/// A report of potential exposure.
public struct Report: Equatable {
    
    /// The 32 bytes of the ed25519 public key used for report verification
    public var reportVerificationPublicKeyBytes: Data
    
    /// The 32 bytes of the temporary contact key.
    public var temporaryContactKeyBytes: Data
    
    /// The start period of the report. Invariant: j_1 > 0.
    public var startIndex: UInt16
    
    /// The end period of the report.
    public var endIndex: UInt16
    
    /// The type of the memo (1 byte).
    public var memoType: MemoType
    
    /// The data of the memo (1 byte or more).
    public var memoData: Data
    
    public init(
        reportVerificationPublicKeyBytes: Data,
        temporaryContactKeyBytes: Data,
        startIndex: UInt16,
        endIndex: UInt16,
        memoType: MemoType,
        memoData: Data
    ) {
        self.reportVerificationPublicKeyBytes = reportVerificationPublicKeyBytes
        self.temporaryContactKeyBytes = temporaryContactKeyBytes
        self.startIndex = startIndex
        self.endIndex = endIndex
        if self.startIndex > self.endIndex {
            self.startIndex = self.endIndex
        }
        self.memoType = memoType
        self.memoData = memoData
    }
    
    /// Returns all temporary contact numbers included in the report.
    public func getTemporaryContactNumbers() -> [TemporaryContactNumber] {
        var temporaryContactKey: TemporaryContactKey? = TemporaryContactKey(
            index: startIndex - 1, // Does not underflow as j_1 > 0.
            reportVerificationPublicKeyBytes: reportVerificationPublicKeyBytes,
            bytes: temporaryContactKeyBytes
        )
        // Ratchet to obtain tck_{j_1}.
        temporaryContactKey = temporaryContactKey?.ratchet()
        return (startIndex..<endIndex).compactMap { _ in
            let temporaryContactNumber = temporaryContactKey?.temporaryContactNumber
            temporaryContactKey = temporaryContactKey?.ratchet()
            return temporaryContactNumber
        }
    }
}

extension ReportAuthorizationKey {
    
    /// Create a report of potential exposure.
    ///
    /// Creating a report reveals *all* temporary contact numbers subsequent to `startIndex`, not just
    /// up to `endIndex`, which is included for convenience.
    ///
    /// Reports are unlinkable from each other **only up to the memo field**. In other words, adding the
    /// same high-entropy data to the memo fields of multiple reports will cause them to be linkable.
    ///
    /// - Parameters:
    ///   - memoType: The type of the report's memo field.
    ///   - memoData: The data of the report's memo field.  Less than 256 bytes.
    ///   - startIndex: The ratchet index of the first temporary contact number in the report. j_1 > 0.
    ///   - endIndex: The ratchet index of the last temporary contact number other users should check.
    /// - Throws: If there is a failure producing the signature.
    /// - Returns: A signed report.
    public func createSignedReport(
        memoType: MemoType,
        memoData: Data,
        startIndex: UInt16,
        endIndex: UInt16
    ) throws -> SignedReport {
        
        // Ensure that j_1 is at least 1.
        var startIndex = startIndex
        if startIndex == 0 {
            startIndex = 1
        }
        
        // Recompute tck_{j_1-1}. This requires recomputing j_1-1 hashes, but
        // creating reports is done infrequently and it means we don't force the
        // caller to have saved all intermediate hashes.
        var temporaryContactKey = self.tck_0
        // initial_temporary_contact_key returns tck_1, so begin iteration at 1.
        for _ in 0..<startIndex-1 {
            temporaryContactKey = temporaryContactKey.ratchet()!
        }
        let report = Report(
            reportVerificationPublicKeyBytes: reportAuthorizationPrivateKey
                .publicKey.rawRepresentation,
            temporaryContactKeyBytes: temporaryContactKey.bytes,
            // Invariant: we have ensured j_1 > 0 above.
            startIndex: startIndex,
            endIndex: endIndex,
            memoType: memoType,
            memoData: memoData
        )
        let signatureBytes = try reportAuthorizationPrivateKey.signature(
            for: report.serializedData()
        )
        return SignedReport(report: report, signatureBytes: signatureBytes)
    }
    
}

/// A signed exposure report, whose source integrity can be verified to produce a `Report`.
public struct SignedReport: Equatable {
    
    /// The report.
    public var report: Report
    
    /// The 64 bytes of the ed25519 signature of the report.
    public var signatureBytes: Data
    
    public init(report: Report, signatureBytes: Data) {
        self.report = report
        self.signatureBytes = signatureBytes
    }
    
    /// Verify the source integrity of the contained `report`.
    public func verify() throws -> Bool {
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: report.reportVerificationPublicKeyBytes
        )
        return publicKey.isValidSignature(
            signatureBytes, for: try report.serializedData()
        )
    }
}
