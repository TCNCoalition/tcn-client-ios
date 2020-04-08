//
//  Created by Zsombor Szabo on 08/04/2020.
//

import Foundation
import CoreBluetooth.CBCharacteristic

extension CBMutableCharacteristic {
    
    /// The characteristic exposed by the primary peripheral service in BLE connection-oriented mode.
    public static var tcnCharacteristic: CBMutableCharacteristic {
        return CBMutableCharacteristic(
            type: .tcnCharacteristic,
            properties: [.read, .write],
            value: nil,
            permissions: [.readable, .writeable]
        )
    }
    
}
