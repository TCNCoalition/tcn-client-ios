//
//  Created by Zsombor Szabo on 08/04/2020.
//

import Foundation
import CoreBluetooth.CBService

extension CBMutableService {
    
    /// The primary peripheral service to be added to the local GATT database in BLE connection-oriented
    /// mode.
    public static var tcnPeripheralService: CBMutableService {
        let service = CBMutableService(
            type: .tcnService,
            primary: true
        )
        service.characteristics = [CBMutableCharacteristic.tcnCharacteristic]
        return service
    }
    
}
