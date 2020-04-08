//
//  Created by Zsombor Szabo on 25/03/2020.
//

import Foundation
import os.log

extension TCNBluetoothServiceImpl {
    
    func didFindTCN(_ tcn: Data) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Did find TCN=%@",
                log: .bluetooth,
                tcn.base64EncodedString()
            )
        }
        self.service?.tcnFinder(tcn)
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
