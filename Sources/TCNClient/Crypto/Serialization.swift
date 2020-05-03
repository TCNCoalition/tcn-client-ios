//
//  Created by Zsombor Szabo on 03/04/2020.
//  

import Foundation

protocol TCNSerializable {
    
    init(serializedData: Data) throws
    
    func serializedData() throws -> Data
    
}

extension Report: TCNSerializable {
    
    public static var minimumSerializedDataLength = 32 + 32 + 2 + 2 + 1 + 1
    
    public init(serializedData: Data) throws {
        guard serializedData.count >= Report.minimumSerializedDataLength else {
            throw CocoaError(.coderInvalidValue)
        }
        self.reportVerificationPublicKeyBytes = serializedData[0..<32]
        self.temporaryContactKeyBytes = serializedData[32..<64]
        self.startIndex = try UInt16(dataRepresentation: serializedData[64..<66])
        self.endIndex = try UInt16(dataRepresentation: serializedData[66..<68])
        self.memoType = try MemoType(dataRepresentation: serializedData[68..<69])
        // Notice, we skip reading the length and go straight reading the memo data.
        self.memoData = serializedData[70..<serializedData.count]
        // Invariant: j_1 > 0
        guard self.startIndex > 0 else {
            throw TCNError.InvalidReportIndex
        }
    }
    
    public func serializedData() throws -> Data {
        do {
            let memoLength = UInt8(memoData.count)
            guard Int(memoLength) == memoData.count else {
                throw TCNError.OversizeMemo(memoData.count)                
            }
            return reportVerificationPublicKeyBytes +
                temporaryContactKeyBytes +
                startIndex.dataRepresentation +
                endIndex.dataRepresentation +
                memoType.dataRepresentation +
                memoLength.dataRepresentation +
            memoData
        }
        catch {
            throw TCNError.OversizeMemo(memoData.count)
        }
    }
    
}

extension SignedReport: TCNSerializable {
    
    public init(serializedData: Data) throws {
        guard serializedData.count >= Report.minimumSerializedDataLength + 64 else {
            throw CocoaError(.coderInvalidValue)
        }
        self.report = try Report(
            serializedData: serializedData[0..<serializedData.count-64]
        )
        self.signatureBytes = serializedData[serializedData.count-64..<serializedData.count]
    }
    
    public func serializedData() throws -> Data {
        return try report.serializedData() + signatureBytes
    }
}

extension TemporaryContactKey: TCNSerializable {
    
    public init(serializedData: Data) throws {
        guard serializedData.count == 2 + 32 + 32 else {
            throw CocoaError(.coderInvalidValue)
        }
        self.index = try UInt16(dataRepresentation: serializedData[0..<2])
        self.reportVerificationPublicKeyBytes = serializedData[2..<34]
        self.bytes = serializedData[34..<66]
    }
    
    public func serializedData() -> Data {
        return index.dataRepresentation + reportVerificationPublicKeyBytes + bytes
    }
    
}

extension ReportAuthorizationKey: TCNSerializable {
    
    public init(serializedData: Data) throws {
        guard serializedData.count == 32 else {
            throw CocoaError(.coderInvalidValue)
        }
        self.reportAuthorizationPrivateKey = try Curve25519PrivateKey(
            rawRepresentation: serializedData
        )
    }
    
    public func serializedData() -> Data {
        return reportAuthorizationPrivateKey.rawRepresentation
    }
    
}
