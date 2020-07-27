//
//  Created by Zsombor Szabo on 25/03/2020.
//

import Foundation
import os.log

extension TCNBluetoothServiceImpl {
    
    func didFindTCN(_ tcn: Data, estimatedDistance: Double? = nil) {
//        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
//            os_log(
//                "Did find TCN=%@ at estimated distance=%.2f",
//                log: .bluetooth,
//                tcn.base64EncodedString(),
//                estimatedDistance ?? -1.0
//            )
//        }
        self.service?.tcnFinder(tcn, estimatedDistance)
    }
    
    func generateTCN() -> Data {
        let tcn = self.service?.tcnGenerator()
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Did generate TCN=%@",
                log: .bluetooth,
                tcn?.base64EncodedString() ?? ""
            )
        }
        return tcn ?? Data()
    }
    
}
