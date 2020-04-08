//
//  Created by Zsombor Szabo on 08/04/2020.
//

import Foundation
import os.log

@available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
extension OSLog {
    
    public static let bluetooth = OSLog(
        subsystem: TCNConstants.domainNameInReverseDotNotationString,
        category: "Bluetooth"
    )
    
}
