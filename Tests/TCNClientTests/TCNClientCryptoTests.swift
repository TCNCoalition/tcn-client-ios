import XCTest
import CryptoKit
@testable import TCNClient

final class TCNClientCryptoTests: XCTestCase {
    
    func testSHA256() {
        let data = "Any data".data(using: .utf8)!
        if #available(iOS 13.2, *) {
            let hash1 = SHA256.hash(data: data).dataRepresentation
            let hash2 = (data as NSData).sha256Digest() as Data
            XCTAssertEqual(hash1, hash2)
        }
    }
    
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
            let serialization = try object.serializedData()
            let newObject = try Report(serializedData: serialization)
            XCTAssertEqual(object, newObject)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testReportSerializationFailureWithNoMemoData() {
        do {
            let object = Report(reportVerificationPublicKeyBytes: Data(count: 32), temporaryContactKeyBytes: Data(count: 32), startIndex: 0, endIndex: 8, memoType: .CoEpiV1, memoData: Data(count: 0))
            let serialization = try object.serializedData()
            XCTAssertThrowsError(try Report(serializedData: serialization))
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testSignedReportSerialization() {
        do {
            let object = SignedReport(report: Report(reportVerificationPublicKeyBytes: Data(count: 32), temporaryContactKeyBytes: Data(count: 32), startIndex: 1, endIndex: 8, memoType: .CoEpiV1, memoData: Data(count: 1)), signatureBytes: Data(count: 64))
            let serialization = try object.serializedData()
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
            let serialization = try object.serializedData()
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
            let signedReportSerialization = try signedReport.serializedData()
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
    
    func testTestVectors() {
        do {
            let expected_rak_bytes = "577cfdae21fee71579211ab02c418ee0948bacab613cf69d0a4a5ae5a1557dbb"
            let expected_rvk_bytes = "fd8deb9d91a13e144ca5b0ce14e289532e040fe0bf922c6e3dadb1e4e2333c78"
            let expected_tck_bytes = [
                "df535b90ac99bec8be3a8add45ce77897b1e7cb1906b5cff1097d3cb142fd9d0",
                "25607e1398836b8882874bd7195a2829a506942c8d45d1e36f772d7d4c12d16e",
                "2bee15dd8e70aa9c4c8e43240eaa735d922984b33fda2a47f919ddd0d5a174cf",
                "67bcaf90bacf4a68eb9c05e433fbadef652082d3e9f1a144c0c33e6c48c9b42d",
                "a5a64f060f1b3b82c8977413b20a391053e339ec56383180efc1bb826bf65493",
                "c7e13775159649342247cea52125402da073a93ed9a36a9f8f813b96913ba1b3",
                "c8c79b595e82a9abbb04c6b16d09225433ab84d9c3c28d27736745d7d3e1d8f2",
                "4c96eb8375eb9afe693a1ef1f1c564676122c8484b3073914749a64d2f61b83a",
                "0a7a2f476f02dd720e88d5f4290656b28ca151919d67c408daa174bef8112b9e",
            ]
            let expected_tcn_bytes = [
                "f4350a4a33e30f2f568898fbe4c4cf34",
                "135eeaa6482b8852fea3544edf6eabf0",
                "d713ce68cf4127bcebde6874c4991e4b",
                "5174e6514d2086565e4ea09a45995191",
                "ccae4f2c3144ad1ed0c2a39613ef0342",
                "3b9e600991369bba3944b6e9d8fda370",
                "dc06a8625c08e946317ad4c89e6ee8a1",
                "9d671457835f2c254722bfd0de76dffc",
                "8b454d28430d3153a500359d9a49ec88",
            ]
            
            let rak = ReportAuthorizationKey(reportAuthorizationPrivateKey: try .init(rawRepresentation: expected_rak_bytes.hexDecodedData()))
            XCTAssertEqual(rak.reportAuthorizationPrivateKey.rawRepresentation.hexEncodedString(), expected_rak_bytes)
            
            //            print("here")
            var tck = rak.initialTemporaryContactKey
            for index in 0..<9 {
                XCTAssertEqual(tck.bytes.hexEncodedString(), expected_tck_bytes[index])
                XCTAssertEqual(tck.temporaryContactNumber.bytes.hexEncodedString(), expected_tcn_bytes[index])
                tck = tck.ratchet()!
            }
            
            let signedReport = try rak.createSignedReport(
                memoType: .CoEpiV1,
                memoData: "symptom data".data(using: .utf8)!,
                startIndex: 2,
                endIndex: 10
            )
            
            XCTAssertEqual(signedReport.report.reportVerificationPublicKeyBytes.hexEncodedString(), expected_rvk_bytes)
            
            
            // This fails because: https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey/3237448-signature
            /*
             XCTAssertEqual(
             try signedReport.serializedData(),
             "fd8deb9d91a13e144ca5b0ce14e289532e040fe0bf922c6e3dadb1e4e2333c78df535b90ac99bec8be3a8add45ce77897b1e7cb1906b5cff1097d3cb142fd9d002000a00000c73796d70746f6d206461746131078ec5367b67a8c793b740626d81ba904789363137b5a313419c0f50b180d8226ecc984bf073ff89cbd9c88fea06bda1f0f368b0e7e88bbe68f15574482904".hexDecodedData()
             )
             */
            
            XCTAssertEqual(
                try signedReport.report.serializedData(),
                "fd8deb9d91a13e144ca5b0ce14e289532e040fe0bf922c6e3dadb1e4e2333c78df535b90ac99bec8be3a8add45ce77897b1e7cb1906b5cff1097d3cb142fd9d002000a00000c73796d70746f6d2064617461"
                    .hexDecodedData()
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
