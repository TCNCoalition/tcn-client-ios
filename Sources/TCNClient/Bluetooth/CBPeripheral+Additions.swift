//
//  Created by Zsombor Szabo on 31/03/2020.
//

import Foundation
import CoreBluetooth.CBPeripheral

extension CBPeripheral {
    
    /// Returns a set of discovered characteristics whose UUID is `uuid` included by the discovered
    /// services.
    /// - Parameter uuid: The UUID to search for.
    /// - Returns: A set of discovered characteristics whose UUID is `uuid` included by the
    ///     discovered services.
    func characteristics(with uuid: CBUUID) -> Set<CBCharacteristic> {
        var result = Set<CBCharacteristic>()
        self.services?.forEach({ (service) in
            service.characteristics?.forEach({ (characteristic) in
                if characteristic.uuid == uuid {
                    result.insert(characteristic)
                }
            })
        })
        return result
    }
    
}
