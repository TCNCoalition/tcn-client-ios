//
//  Created by Zsombor Szabo on 03/04/2020.
//

import Foundation

/// A Bluetooth service that implements the TCN protocol.
public class TCNBluetoothService: NSObject {
    
    /// The block that is called whenever the service needs a new TCN for sharing.
    public var tcnGenerator: () -> Data
    
    /// The block that is called whenever the service finds a TCN.
    public var tcnFinder: (Data, Double?) -> Void
    
    /// The block that is called whenever a critical error occurs, like no permission to access Bluetooth.
    public var errorHandler: (Error) -> Void
    
    private var tcnBluetoothServiceImpl = TCNBluetoothServiceImpl()
    
    public init(
        tcnGenerator: @escaping () -> Data,
        tcnFinder: @escaping (Data, Double?) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        self.tcnGenerator = tcnGenerator
        self.tcnFinder = tcnFinder
        self.errorHandler = errorHandler
        super.init()
        // Service is a weak property to avoid a retain cycle.
        self.tcnBluetoothServiceImpl.service = self
    }
    
    /// Starts the service.
    public func start() {
        self.tcnBluetoothServiceImpl.start()
    }
    
    /// Stops the service.
    public func stop() {
        self.tcnBluetoothServiceImpl.stop()
    }
    
}
