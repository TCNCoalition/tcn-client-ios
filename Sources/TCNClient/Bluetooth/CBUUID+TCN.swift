//
//  Created by Zsombor Szabo on 08/04/2020.
//

import Foundation
import CoreBluetooth.CBUUID

extension CBUUID {
    
    public static let tcnService = CBUUID(string: TCNConstants.UUIDServiceString)
    
    public static let tcnCharacteristic = CBUUID(string: TCNConstants.UUIDCharacteristicString)
    
}
