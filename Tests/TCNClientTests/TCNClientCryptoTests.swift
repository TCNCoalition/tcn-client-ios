import XCTest
@testable import TCNClient

final class TCNClientCryptoTests: XCTestCase {
    
    func testReportAuthorizationKeySerialization() {
        do {
            let key = ReportAuthorizationKey()
            let serialization = key.serializedData()
            let newKey = try ReportAuthorizationKey(serializedData: serialization)
            XCTAssertEqual(key, newKey)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testTemporaryContactKeySerialization() {
        do {
            let key = TemporaryContactKey(index: 0, reportVerificationPublicKeyBytes: Data(count: 32), bytes: Data(count: 32))
            let serialization = key.serializedData()
            let newKey = try TemporaryContactKey(serializedData: serialization)
            XCTAssertEqual(key, newKey)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testTemporaryContactKeySerializationFailure() {
        let key = TemporaryContactKey(index: 0, reportVerificationPublicKeyBytes: Data(count: 33), bytes: Data(count: 32))
        let serialization = key.serializedData()
        XCTAssertThrowsError(try TemporaryContactKey(serializedData: serialization))
    }
    
    func testReportSerialization() {
        do {
            let object = Report(reportVerificationPublicKeyBytes: Data(count: 32), temporaryContactKeyBytes: Data(count: 32), startIndex: 1, endIndex: 8, memoType: .CoEpiV1, memoData: Data(count: 100))
            let serialization = object.serializedData()
            let newObject = try Report(serializedData: serialization)
            XCTAssertEqual(object, newObject)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testReportSerializationFailureWithNoMemoData() {
        let object = Report(reportVerificationPublicKeyBytes: Data(count: 32), temporaryContactKeyBytes: Data(count: 32), startIndex: 0, endIndex: 8, memoType: .CoEpiV1, memoData: Data(count: 0))
        let serialization = object.serializedData()
        XCTAssertThrowsError(try Report(serializedData: serialization))
    }
    
    func testSignedReportSerialization() {
        do {
            let object = SignedReport(report: Report(reportVerificationPublicKeyBytes: Data(count: 32), temporaryContactKeyBytes: Data(count: 32), startIndex: 1, endIndex: 8, memoType: .CoEpiV1, memoData: Data(count: 1)), signatureBytes: Data(count: 64))
            let serialization = object.serializedData()
            let newObject = try SignedReport(serializedData: serialization)
            XCTAssertEqual(object, newObject)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testSignedReportSerializationFailureWithBadSignatureLength() {
        do {
            let object = SignedReport(report: Report(reportVerificationPublicKeyBytes: Data(count: 32), temporaryContactKeyBytes: Data(count: 32), startIndex: 1, endIndex: 8, memoType: .CoEpiV1, memoData: Data(count: 1)), signatureBytes: Data(count: 68))
            let serialization = object.serializedData()
            let newObject = try SignedReport(serializedData: serialization)
            XCTAssertNotEqual(object, newObject)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testBasicReadWriteRoundTrip() {
        do {
            let reportAuthorizationKey = ReportAuthorizationKey(reportAuthorizationPrivateKey: .init())
            let reportAuthorizationKeySerialization = reportAuthorizationKey.serializedData()
            let newReportAuthorizationKey = try ReportAuthorizationKey(serializedData: reportAuthorizationKeySerialization)
            XCTAssertEqual(reportAuthorizationKey, newReportAuthorizationKey)
            
            let initialTemporaryContactKey = reportAuthorizationKey.initialTemporaryContactKey
            let initialTemporaryContactKeySerialization = initialTemporaryContactKey.serializedData()
            let newInitialTemporaryContactKey = try TemporaryContactKey(serializedData: initialTemporaryContactKeySerialization)
            XCTAssertEqual(initialTemporaryContactKey, newInitialTemporaryContactKey)
            
            let signedReport = try reportAuthorizationKey.createSignedReport(memoType: .CoEpiV1, memoData: "symptom data".data(using: .utf8)!, startIndex: 20, endIndex: 100)
            let signedReportSerialization = signedReport.serializedData()
            let newSignedReport = try SignedReport(serializedData: signedReportSerialization)
            XCTAssertEqual(signedReport, newSignedReport)
            
            // Valid reports should verify correctly
            _ = try signedReport.verify()
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testTemporaryContactNumbersAndReportThem() {
        do {
            // Generate a report authorization key.  This key represents the capability
            // to publish a report about a collection of derived temporary contact numbers.
            let reportAuthorizationKey = ReportAuthorizationKey(reportAuthorizationPrivateKey: .init())
            
            // Use the temporary contact key ratchet mechanism to compute a list of contact
            // event numbers.
            var temporaryContactKey = reportAuthorizationKey.initialTemporaryContactKey // cek <- cek_1
            var temporaryContactNumbers = [TemporaryContactNumber]()
            for _ in 0..<100 {
                temporaryContactNumbers.append(temporaryContactKey.temporaryContactNumber)
                temporaryContactKey = temporaryContactKey.ratchet()!
            }
            
            // Prepare a report about a subset of the temporary contact numbers.
            // Report creation can only fail if the memo data is too long
            let signedReport = try reportAuthorizationKey.createSignedReport(
                memoType: .CoEpiV1, // The memo type
                memoData: "symptom data".data(using: .utf8)!, // The memo data
                startIndex: 20, // Index of the first TCN to disclose
                endIndex: 90 // Index of the last TCN to check
            )
            
            // Verify the source integrity of the report...
            XCTAssertTrue(try signedReport.verify())
            
            // ...allowing the disclosed TCNs to be recomputed.
            let recomputedTemporaryContactNumbers = signedReport.report.getTemporaryContactNumbers()
            
            // Check that the recomputed TCNs match the originals.
            // The slice is offset by 1 because tcn_0 is not included.
            XCTAssertEqual(
                recomputedTemporaryContactNumbers,
                Array(temporaryContactNumbers[(20 - 1)..<(90 - 1)])
            )
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    static var allTests = [
        ("testReportAuthorizationKeySerialization", testReportAuthorizationKeySerialization),
        ("testTemporaryContactKeySerialization", testTemporaryContactKeySerialization),
        ("testTemporaryContactKeySerializationFailure", testTemporaryContactKeySerializationFailure),
        ("testReportSerialization", testReportSerialization),
        ("testReportSerializationFailureWithNoMemoData", testReportSerializationFailureWithNoMemoData),
        ("testSignedReportSerialization", testSignedReportSerialization),
        ("testSignedReportSerializationFailureWithBadSignatureLength", testSignedReportSerializationFailureWithBadSignatureLength),
        ("testBasicReadWriteRoundTrip", testBasicReadWriteRoundTrip),
        ("testTemporaryContactNumbersAndReportThem", testTemporaryContactNumbersAndReportThem),
    ]
}
