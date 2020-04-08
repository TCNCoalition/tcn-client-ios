import XCTest
@testable import TCNClient
import CoreBluetooth

final class TCNClientBluetoothTests: XCTestCase {
    
    func testCoreBluetoothInit() {
        let service = CBMutableService.tcnPeripheralService
        XCTAssertEqual(CBUUID.tcnService, service.uuid)
        XCTAssertEqual(true, service.isPrimary)
        XCTAssertNotNil(service.characteristics?.first)
        let characteristic = CBMutableCharacteristic.tcnCharacteristic
        XCTAssertNil(characteristic.value)
        XCTAssertEqual(characteristic.uuid, CBUUID.tcnCharacteristic)
        XCTAssertEqual([.write, .read], characteristic.properties)
        XCTAssertEqual([.writeable, .readable], characteristic.permissions)
    }

    static var allTests = [
        ("testCoreBluetoothInit", testCoreBluetoothInit),
    ]
}
