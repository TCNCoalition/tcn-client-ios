//
//  Created by Zsombor Szabo on 11/03/2020.
//

import Foundation
import CoreBluetooth
#if canImport(UIKit) && !os(watchOS)
import UIKit.UIApplication
#endif
import os.log

extension TimeInterval {
    
    /// The time interval after which the peripheral connecting operation will time out and canceled.
    public static let peripheralConnectingTimeout: TimeInterval = 8
    
}

extension CBCentralManager {
    
    #if os(watchOS) || os(tvOS)
    public static let maxNumberOfConcurrentPeripheralConnections = 2
    #else
    /// The maximum number of concurrent peripheral connections we allow the central manager to have,
    /// based on platform (and other) limitations.
    public static let maxNumberOfConcurrentPeripheralConnections = 5
    #endif
    
}

/// A Bluetooth service that implements the TCN protocol.
class TCNBluetoothServiceImpl: NSObject {
    
    weak var service: TCNBluetoothService?
    
    private var dispatchQueue: DispatchQueue = DispatchQueue(
        label: TCNConstants.domainNameInReverseDotNotationString
    )
    
    private var centralManager: CBCentralManager?
    
    private var restoredPeripherals: [CBPeripheral]?
    
    private var discoveredPeripherals = Set<CBPeripheral>()
    
    private var connectingTimeoutTimersForPeripheralIdentifiers =
        [UUID : Timer]()
    
    private var connectingPeripheralIdentifiers = Set<UUID>() {
        didSet {
            self.configureBackgroundTaskIfNeeded()
        }
    }
    
    private var connectedPeripheralIdentifiers = Set<UUID>() {
        didSet {
            self.configureBackgroundTaskIfNeeded()
        }
    }
    
    private var shortTemporaryIdentifiersOfPeripheralsToWhichWeDidWriteTCNTo = Set<Data>()
    
    private var connectingConnectedPeripheralIdentifiers: Set<UUID> {
        self.connectingPeripheralIdentifiers.union(
            self.connectedPeripheralIdentifiers
        )
    }
    
    private var discoveringServicesPeripheralIdentifiers = Set<UUID>()
    
    private var characteristicsBeingRead = Set<CBCharacteristic>()
    
    private var characteristicsBeingWritten = Set<CBCharacteristic>()
    
    private var peripheralManager: CBPeripheralManager?
    
    private var tcnsForRemoteDeviceIdentifiers = [UUID : Data]()
    
    private var estimatedDistancesForRemoteDeviceIdentifiers = [UUID : Double]()
    
    private var peripheralsToReadTCNFrom = Set<CBPeripheral>()
    
    private var peripheralsToWriteTCNTo = Set<CBPeripheral>()
    
    private var peripheralsToConnect: Set<CBPeripheral> {
        return Set(peripheralsToReadTCNFrom).union(Set(peripheralsToWriteTCNTo))
    }
    
    private func configureBackgroundTaskIfNeeded() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
        if self.connectingPeripheralIdentifiers.isEmpty &&
            self.connectedPeripheralIdentifiers.isEmpty {
            self.endBackgroundTaskIfNeeded()
        }
        else {
            self.beginBackgroundTaskIfNeeded()
        }
        #endif
    }
    
    // macCatalyst apps do not need background tasks.
    // watchOS apps do not have background tasks.
    #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?
    
    private func beginBackgroundTaskIfNeeded() {
        guard self.backgroundTaskIdentifier == nil else { return }
        self.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Did expire background task=%d",
                    log: .bluetooth,
                    self.backgroundTaskIdentifier?.rawValue ?? 0
                )
            }
            self.endBackgroundTaskIfNeeded()
        }
        if let task = self.backgroundTaskIdentifier {
            if task == .invalid {
                if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    os_log(
                        "Begin background task failed",
                        log: .bluetooth,
                        type: .error
                    )
                }
            }
            else {
                if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    os_log(
                        "Begin background task=%d",
                        log: .bluetooth,
                        task.rawValue
                    )
                }
            }
        }
    }
    
    private func endBackgroundTaskIfNeeded() {
        if let identifier = self.backgroundTaskIdentifier {
            UIApplication.shared.endBackgroundTask(identifier)
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "End background task=%d",
                    log: .bluetooth,
                    self.backgroundTaskIdentifier?.rawValue ??
                        UIBackgroundTaskIdentifier.invalid.rawValue
                )
            }
            self.backgroundTaskIdentifier = nil
        }
    }
    #endif
    
    override init() {
        super.init()
        // macCatalyst apps do not need background support.
        // watchOS apps do not have background support.
        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationWillEnterForegroundNotification(_:)),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }
    
    deinit {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }
    
    // MARK: - Notifications
    
    @objc func applicationWillEnterForegroundNotification(
        _ notification: Notification
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log("Application will enter foreground", log: .bluetooth)
        }
        self.dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            // Bug workaround: If the user toggles Bluetooth while the app was
            // in the background, then scanning fails when the app becomes
            // active. Restart Bluetooth scanning to work around this issue.
            if self.centralManager?.isScanning ?? false {
                self.centralManager?.stopScan()
                self._startScan()
            }
        }
    }
    
    // MARK: -
    
    /// Returns true if the service is started.
    var isStarted: Bool {
        return self.centralManager != nil
    }
    
    /// Starts the service.
    func start() {
        self.dispatchQueue.async {
            guard self.centralManager == nil else {
                return
            }
            self.centralManager = CBCentralManager(
                delegate: self,
                queue: self.dispatchQueue,
                options: [
                    CBCentralManagerOptionRestoreIdentifierKey:
                        TCNConstants.domainNameInReverseDotNotationString,
                    // Warn user if Bluetooth is turned off.
                    CBCentralManagerOptionShowPowerAlertKey :
                        NSNumber(booleanLiteral: true),
                ]
            )
            self.peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: self.dispatchQueue,
                options: [
                    CBPeripheralManagerOptionRestoreIdentifierKey:
                        TCNConstants.domainNameInReverseDotNotationString
                ]
            )
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Service started",
                    log: .bluetooth
                )
            }
        }
    }
    
    /// Stops the service.
    func stop() {
        self.dispatchQueue.async {
            self.stopCentralManager()
            self.centralManager?.delegate = nil
            self.centralManager = nil
            self.stopPeripheralManager()
            self.peripheralManager?.delegate = nil
            self.peripheralManager = nil
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Service stopped",
                    log: .bluetooth
                )
            }
        }
    }
    
    private func stopCentralManager() {
        self.connectingTimeoutTimersForPeripheralIdentifiers.values.forEach {
            $0.invalidate()
        }
        self.connectingTimeoutTimersForPeripheralIdentifiers.removeAll()
        self.discoveredPeripherals.forEach { self.flushPeripheral($0) }
        self.discoveredPeripherals.removeAll()
        self.connectingPeripheralIdentifiers.removeAll()
        self.connectedPeripheralIdentifiers.removeAll()
        self.discoveringServicesPeripheralIdentifiers.removeAll()
        self.characteristicsBeingRead.removeAll()
        self.characteristicsBeingWritten.removeAll()
        self.peripheralsToReadTCNFrom.removeAll()
        self.peripheralsToWriteTCNTo.removeAll()
        self.shortTemporaryIdentifiersOfPeripheralsToWhichWeDidWriteTCNTo.removeAll()
        self.tcnsForRemoteDeviceIdentifiers.removeAll()
        self.estimatedDistancesForRemoteDeviceIdentifiers.removeAll()
        if self.centralManager?.isScanning ?? false {
            self.centralManager?.stopScan()
        }
    }
    
    private func stopPeripheralManager() {
        if self.peripheralManager?.isAdvertising ?? false {
            self.peripheralManager?.stopAdvertising()
        }
        if self.peripheralManager?.state == .poweredOn {
            self.peripheralManager?.removeAllServices()
        }
    }
    
    private func connectPeripheralsIfNeeded() {
        guard self.peripheralsToConnect.count > 0 else {
            return
        }
        guard self.connectingConnectedPeripheralIdentifiers.count <
            CBCentralManager.maxNumberOfConcurrentPeripheralConnections else {
                return
        }
        let disconnectedPeripherals = self.peripheralsToConnect.filter {
            $0.state == .disconnected || $0.state == .disconnecting
        }
        disconnectedPeripherals.prefix(
            CBCentralManager.maxNumberOfConcurrentPeripheralConnections -
                self.connectingConnectedPeripheralIdentifiers.count
        ).forEach {
            self.connectIfNeeded(peripheral: $0)
        }
    }
    
    private func connectIfNeeded(peripheral: CBPeripheral) {
        guard let centralManager = centralManager else {
            return
        }
        if peripheral.state != .connected {
            if peripheral.state != .connecting {
                self.centralManager?.connect(peripheral, options: nil)
                if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    os_log(
                        "Central manager connecting peripheral (uuid=%@ name='%@')",
                        log: .bluetooth,
                        peripheral.identifier.description,
                        peripheral.name ?? ""
                    )
                }
                self.setupConnectingTimeoutTimer(for: peripheral)
                self.connectingPeripheralIdentifiers.insert(peripheral.identifier)
            }
        }
        else {
            self._centralManager(centralManager, didConnect: peripheral)
        }
    }
    
    private func setupConnectingTimeoutTimer(for peripheral: CBPeripheral) {
        let timer = Timer.init(
            timeInterval: .peripheralConnectingTimeout,
            target: self,
            selector: #selector(_connectingTimeoutTimerFired(timer:)),
            userInfo: ["peripheral" : peripheral],
            repeats: false
        )
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.connectingTimeoutTimersForPeripheralIdentifiers[
            peripheral.identifier]?.invalidate()
        self.connectingTimeoutTimersForPeripheralIdentifiers[
            peripheral.identifier] = timer
    }
    
    @objc private func _connectingTimeoutTimerFired(timer: Timer) {
        let userInfo = timer.userInfo
        self.dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            guard let dict = userInfo as? [AnyHashable : Any],
                let peripheral = dict["peripheral"] as? CBPeripheral else {
                    return
            }
            if peripheral.state != .connected {
                if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    os_log(
                        "Connecting did time out for peripheral (uuid=%@ name='%@')",
                        log: .bluetooth,
                        peripheral.identifier.description,
                        peripheral.name ?? ""
                    )
                }
                self.flushPeripheral(peripheral)
            }
        }
    }
    
    private func flushPeripheral(_ peripheral: CBPeripheral) {
        self.peripheralsToReadTCNFrom.remove(peripheral)
        self.peripheralsToWriteTCNTo.remove(peripheral)
        self.tcnsForRemoteDeviceIdentifiers[peripheral.identifier] = nil
        self.estimatedDistancesForRemoteDeviceIdentifiers[peripheral.identifier] = nil
        self.discoveredPeripherals.remove(peripheral)
        self.cancelConnectionIfNeeded(for: peripheral)
    }
    
    private func cancelConnectionIfNeeded(for peripheral: CBPeripheral) {
        self.connectingTimeoutTimersForPeripheralIdentifiers[
            peripheral.identifier]?.invalidate()
        self.connectingTimeoutTimersForPeripheralIdentifiers[
            peripheral.identifier] = nil
        if peripheral.state == .connecting || peripheral.state == .connected {
            self.centralManager?.cancelPeripheralConnection(peripheral)
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Central manager cancelled peripheral (uuid=%@ name='%@') connection",
                    log: .bluetooth,
                    peripheral.identifier.description,
                    peripheral.name ?? ""
                )
            }
        }
        peripheral.delegate = nil
        self.connectingPeripheralIdentifiers.remove(peripheral.identifier)
        self.connectedPeripheralIdentifiers.remove(peripheral.identifier)
        self.discoveringServicesPeripheralIdentifiers.remove(peripheral.identifier)
        peripheral.services?.forEach {
            $0.characteristics?.forEach {
                self.characteristicsBeingRead.remove($0)
                self.characteristicsBeingWritten.remove($0)
            }
        }
        self.connectPeripheralsIfNeeded()
    }
}

extension TCNBluetoothServiceImpl: CBCentralManagerDelegate {
    
    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String : Any]
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Central manager will restore state=%@",
                log: .bluetooth,
                dict.description
            )
        }
        // Store the peripherals so we can cancel the connections to them when
        // the central manager's state changes to `poweredOn`.
        self.restoredPeripherals =
            dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Central manager did update state=%@",
                log: .bluetooth,
                String(describing: central.state.rawValue)
            )
        }
        self.stopCentralManager()
        switch central.state {
            case .poweredOn:
                self.restoredPeripherals?.forEach({
                    central.cancelPeripheralConnection($0)
                })
                self.restoredPeripherals = nil
                self._startScan()
            default:
                ()
        }
    }
    
    private func _startScan() {
        guard let central = self.centralManager else { return }
        #if targetEnvironment(macCatalyst)
        // CoreBluetooth on macCatalyst doesn't discover the peripheral services
        // of iOS apps in the background-running or suspended state.
        // Therefore we scan for everything.
        let services: [CBUUID]? = nil
        #else
        let services: [CBUUID] = [.tcnService]
        #endif
        let options: [String : Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey :
                NSNumber(booleanLiteral: true)
        ]
        central.scanForPeripherals(
            withServices: services,
            options: options
        )
        #if targetEnvironment(macCatalyst)
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Central manager scanning for peripherals with services=%@ options=%@",
                log: .bluetooth,
                services ?? "",
                options.description
            )
        }
        #else
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Central manager scanning for peripherals with services=%@ options=%@",
                log: .bluetooth,
                services,
                options.description
            )
        }
        #endif
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        // Only Android can enable advertising data in the service data field.
        let isAndroid = ((advertisementData[CBAdvertisementDataServiceDataKey]
            as? [CBUUID : Data])?[.tcnService] != nil)
        
        let estimatedDistanceMeters = getEstimatedDistanceMeters(
            RSSI: RSSI.doubleValue,
            measuredRSSIAtOneMeter: getMeasuredRSSIAtOneMeter(
                advertisementData: advertisementData,
                hintIsAndroid: isAndroid
            )
        )
        self.estimatedDistancesForRemoteDeviceIdentifiers[
            peripheral.identifier] = estimatedDistanceMeters
        
//        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
//            os_log(
//                "Central manager did discover peripheral (uuid=%@ new=%d name='%@') RSSI=%d (estimatedDistance=%.2f)",
//                log: .bluetooth,
//                peripheral.identifier.description,
//                !self.discoveredPeripherals.contains(peripheral),
//                peripheral.name ?? "",
//                RSSI.intValue,
//                estimatedDistanceMeters
//            )
//        }
        
//        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
//            os_log(
//                "Central manager did discover peripheral (uuid=%@ new=%d name='%@') RSSI=%d (estimatedDistance=%.2f) advertisementData=%@",
//                log: .bluetooth,
//                peripheral.identifier.description,
//                !self.discoveredPeripherals.contains(peripheral),
//                peripheral.name ?? "",
//                RSSI.intValue,
//                estimatedDistanceMeters,
//                advertisementData.description
//            )
//        }
        
        self.discoveredPeripherals.insert(peripheral)
        
        // Did we find a TCN from the peripheral already?
        if let tcn = self.tcnsForRemoteDeviceIdentifiers[peripheral.identifier] {
            self.didFindTCN(tcn, estimatedDistance: self.estimatedDistancesForRemoteDeviceIdentifiers[peripheral.identifier])
        }
        else {
            let isConnectable = (advertisementData[
                CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
            
            // Check if we can extract TCN from service data
            if let advertisementDataServiceData = advertisementData[CBAdvertisementDataServiceDataKey]
                as? [CBUUID : Data],
                let serviceData = advertisementDataServiceData[.tcnService] {
                
                // The service data = bridged TCN + first 4 bytes of the current TCN.
                // When the Android bridges a TCN of nearby iOS devices, the
                // last 4 bytes are different than the first 4 bytes.
                guard serviceData.count >= 16 else {
                    return
                }
                
                let tcn = Data(serviceData[0..<16])
                self.tcnsForRemoteDeviceIdentifiers[peripheral.identifier] = tcn
                self.didFindTCN(tcn, estimatedDistance: self.estimatedDistancesForRemoteDeviceIdentifiers[peripheral.identifier])
                
                if serviceData.count == 16 + 4 {
                    let shortTemporaryIdentifier = Data(serviceData[16..<20])
                                    
                    // The remote device is an Android one. Write a TCN to it,
                    // because it can not find the TCN of this iOS device while this
                    // iOS device is in the background, which is most of the time.
                    // But only write if we haven't already.
                    if isConnectable && !self.shortTemporaryIdentifiersOfPeripheralsToWhichWeDidWriteTCNTo.contains(shortTemporaryIdentifier)  {
                        self.peripheralsToWriteTCNTo.insert(peripheral)
                        self.connectPeripheralsIfNeeded()
                        if self.shortTemporaryIdentifiersOfPeripheralsToWhichWeDidWriteTCNTo.count > 65536 {
                            // Ensure our list doesn't grow too much...
                            self.shortTemporaryIdentifiersOfPeripheralsToWhichWeDidWriteTCNTo.removeFirst()
                        }
                        self.shortTemporaryIdentifiersOfPeripheralsToWhichWeDidWriteTCNTo.insert(shortTemporaryIdentifier)
                    }
                }
            }
            else {
                if isConnectable {
                    // The remote device is an iOS one. Read its TCN.
                    self.peripheralsToReadTCNFrom.insert(peripheral)
                    self.connectPeripheralsIfNeeded()
                }
            }
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Central manager did connect peripheral (uuid=%@ name='%@')",
                log: .bluetooth,
                peripheral.identifier.description,
                peripheral.name ?? ""
            )
        }
        self.connectingTimeoutTimersForPeripheralIdentifiers[
            peripheral.identifier]?.invalidate()
        self.connectingTimeoutTimersForPeripheralIdentifiers[
            peripheral.identifier] = nil
        self.connectingPeripheralIdentifiers.remove(peripheral.identifier)
        // Bug workaround: Ignore duplicate connect callbacks from CoreBluetooth.
        guard !self.connectedPeripheralIdentifiers.contains(
            peripheral.identifier) else {
                return
        }
        self.connectedPeripheralIdentifiers.insert(peripheral.identifier)
        self._centralManager(central, didConnect: peripheral)
    }
    
    func _centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        self.discoverServices(for: peripheral)
    }
    
    private func discoverServices(for peripheral: CBPeripheral) {
        guard !self.discoveringServicesPeripheralIdentifiers.contains(
            peripheral.identifier) else {
                return
        }
        self.discoveringServicesPeripheralIdentifiers.insert(peripheral.identifier)
        peripheral.delegate = self
        if peripheral.services == nil {
            let services: [CBUUID] = [.tcnService]
            peripheral.discoverServices(services)
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') discovering services=%@",
                    log: .bluetooth,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    services)
            }
        }
        else {
            self._peripheral(peripheral, didDiscoverServices: nil)
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Central manager did fail to connect peripheral (uuid=%@ name='%@') error=%@",
                log: .bluetooth,
                type:.error,
                peripheral.identifier.description,
                peripheral.name ?? "",
                error as CVarArg? ?? ""
            )
        }
        if #available(iOS 12.0, macOS 10.14, macCatalyst 13.0, tvOS 12.0,
            watchOS 5.0, *) {
            if let error = error as? CBError,
                error.code == CBError.operationNotSupported {
                self.peripheralsToReadTCNFrom.remove(peripheral)
                self.peripheralsToWriteTCNTo.remove(peripheral)
            }
        }
        self.cancelConnectionIfNeeded(for: peripheral)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if let error = error {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Central manager did disconnect peripheral (uuid=%@ name='%@') error=%@",
                    log: .bluetooth,
                    type:.error,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    error as CVarArg
                )
            }
        }
        else {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Central manager did disconnect peripheral (uuid=%@ name='%@')",
                    log: .bluetooth,
                    peripheral.identifier.description,
                    peripheral.name ?? ""
                )
            }
        }
        self.cancelConnectionIfNeeded(for: peripheral)
    }
}

extension TCNBluetoothServiceImpl: CBPeripheralDelegate {
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error = error {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did discover services error=%@",
                    log: .bluetooth,
                    type:.error,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    error as CVarArg
                )
            }
        }
        else {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did discover services",
                    log: .bluetooth,
                    peripheral.identifier.description,
                    peripheral.name ?? ""
                )
            }
        }
        self._peripheral(peripheral, didDiscoverServices: error)
    }
    
    func _peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        self.discoveringServicesPeripheralIdentifiers.remove(peripheral.identifier)
        guard error == nil else {
            self.cancelConnectionIfNeeded(for: peripheral)
            return
        }
        guard let services = peripheral.services, services.count > 0 else {
            self.peripheralsToReadTCNFrom.remove(peripheral)
            self.peripheralsToWriteTCNTo.remove(peripheral)
            self.cancelConnectionIfNeeded(for: peripheral)
            return
        }
        let servicesWithCharacteristicsToDiscover = services.filter {
            $0.characteristics == nil
        }
        if servicesWithCharacteristicsToDiscover.count == 0 {
            self.startTransfers(for: peripheral)
        }
        else {
            servicesWithCharacteristicsToDiscover.forEach { service in
                let characteristics: [CBUUID] = [.tcnCharacteristic]
                peripheral.discoverCharacteristics(characteristics, for: service)
                if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    os_log(
                        "Peripheral (uuid=%@ name='%@') discovering characteristics=%@ for service=%@",
                        log: .bluetooth,
                        peripheral.identifier.description,
                        peripheral.name ?? "",
                        characteristics.description,
                        service.description
                    )
                }
            }
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did discover characteristics for service=%@ error=%@",
                    log: .bluetooth,
                    type:.error,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    service.description,
                    error as CVarArg
                )
            }
        }
        else {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did discover characteristics for service=%@",
                    log: .bluetooth,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    service.description
                )
            }
        }
        guard error == nil, let services = peripheral.services else {
            self.cancelConnectionIfNeeded(for: peripheral)
            return
        }
        let servicesWithCharacteristicsToDiscover = services.filter {
            $0.characteristics == nil
        }
        // Have we discovered the characteristics of all the services, yet?
        if servicesWithCharacteristicsToDiscover.count == 0 {
            self.startTransfers(for: peripheral)
        }
    }
    
    private func shouldReadTCN(from peripheral: CBPeripheral) -> Bool {
        return self.peripheralsToReadTCNFrom.contains(peripheral)
    }
    
    private func shouldWriteTCN(to peripheral: CBPeripheral) -> Bool {
        return self.peripheralsToWriteTCNTo.contains(peripheral)
    }
    
    private func startTransfers(for peripheral: CBPeripheral) {
        guard let services = peripheral.services else {
            self.cancelConnectionIfNeeded(for: peripheral)
            return
        }
        services.forEach { service in
            self._peripheral(
                peripheral,
                didDiscoverCharacteristicsFor: service,
                error: nil
            )
        }
    }
    
    func _peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            self.cancelConnectionIfNeeded(for: peripheral)
            return
        }
        
        if let tcnCharacteristic = service.characteristics?.first(where: {
            $0.uuid == .tcnCharacteristic
        }) {
            // Read the number, if needed.
            if self.shouldReadTCN(from: peripheral) {
                if !self.characteristicsBeingRead.contains(tcnCharacteristic) {
                    self.characteristicsBeingRead.insert(tcnCharacteristic)
                    
                    peripheral.readValue(for: tcnCharacteristic)
                    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                        os_log(
                            "Peripheral (uuid=%@ name='%@') reading value for characteristic=%@ for service=%@",
                            log: .bluetooth,
                            peripheral.identifier.description,
                            peripheral.name ?? "",
                            tcnCharacteristic.description,
                            service.description
                        )
                    }
                }
            } // Write the number, if needed.
            else if self.shouldWriteTCN(to: peripheral) {
                if !self.characteristicsBeingWritten.contains(tcnCharacteristic) {
                    self.characteristicsBeingWritten.insert(tcnCharacteristic)
                    
                    let tcn = generateTCN()
                    let value = tcn
                    
                    peripheral.writeValue(
                        value,
                        for: tcnCharacteristic,
                        type: .withResponse
                    )
                    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                        os_log(
                            "Peripheral (uuid=%@ name='%@') writing value for characteristic=%@ for service=%@",
                            log: .bluetooth,
                            peripheral.identifier.description,
                            peripheral.name ?? "",
                            tcnCharacteristic.description,
                            service.description
                        )
                    }
                }
                
            }
        }
        else {
            self.cancelConnectionIfNeeded(for: peripheral)
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did update value for characteristic=%@ for service=%@ error=%@",
                    log: .bluetooth,
                    type:.error,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    characteristic.description,
                    characteristic.service?.description ?? "",
                    error as CVarArg
                )
            }
        }
        else {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did update value=%{iec-bytes}d for characteristic=%@ for service=%@",
                    log: .bluetooth,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    characteristic.value?.count ?? 0,
                    characteristic.description,
                    characteristic.service?.description ?? ""
                )
            }
        }
        self.characteristicsBeingRead.remove(characteristic)
        do {
            guard error == nil else {
                return
            }
            guard let value = characteristic.value, value.count >= 16 else {
                throw CBATTError(.invalidPdu)
            }
            let tcn = Data(value[0..<16])
            self.tcnsForRemoteDeviceIdentifiers[peripheral.identifier] = tcn
            self.didFindTCN(tcn, estimatedDistance: self.estimatedDistancesForRemoteDeviceIdentifiers[peripheral.identifier])
        }
        catch {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Processing value failed=%@",
                    log: .bluetooth,
                    type:.error,
                    error as CVarArg
                )
            }
        }
        let allCharacteristics = peripheral.characteristics(with: .tcnCharacteristic)
        if self.characteristicsBeingRead
            .intersection(allCharacteristics).isEmpty {
            self.peripheralsToReadTCNFrom.remove(peripheral)
            self.cancelConnectionIfNeeded(for: peripheral)
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did write value for characteristic=%@ for service=%@ error=%@",
                    log: .bluetooth,
                    type:.error,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    characteristic.description,
                    characteristic.service?.description ?? "",
                    error as CVarArg
                )
            }
        }
        else {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral (uuid=%@ name='%@') did write value for characteristic=%@ for service=%@",
                    log: .bluetooth,
                    peripheral.identifier.description,
                    peripheral.name ?? "",
                    characteristic.description,
                    characteristic.service?.description ?? ""
                )
            }
        }
        self.characteristicsBeingWritten.remove(characteristic)
        let allCharacteristics = peripheral.characteristics(with: .tcnCharacteristic)
        if self.characteristicsBeingWritten
            .intersection(allCharacteristics).isEmpty {
            self.peripheralsToWriteTCNTo.remove(peripheral)
            self.cancelConnectionIfNeeded(for: peripheral)
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didModifyServices invalidatedServices: [CBService]
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Peripheral (uuid=%@ name='%@') did modify services=%@",
                log: .bluetooth,
                peripheral.identifier.description,
                peripheral.name ?? "",
                invalidatedServices
            )
        }
        if invalidatedServices.contains(where: {$0.uuid == .tcnService}) {
            self.flushPeripheral(peripheral)
        }
    }
}

extension TCNBluetoothServiceImpl: CBPeripheralManagerDelegate {
    
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        willRestoreState dict: [String : Any]
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Peripheral manager will restore state=%@",
                log: .bluetooth,
                dict.description
            )
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Peripheral manager did update state=%@",
                log: .bluetooth,
                String(describing: peripheral.state.rawValue)
            )
        }
        self._peripheralManagerDidUpdateState(peripheral)
    }
    
    func _peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        //    if #available(OSX 10.15, macCatalyst 13.1, iOS 13.1, tvOS 13.0, watchOS 6.0, *) {
        //      self.service?.bluetoothAuthorization =
        //        BluetoothAuthorization(
        //          cbManagerAuthorization: CBManager.authorization
        //        ) ?? .notDetermined
        //    }
        //    else if #available(OSX 10.15, macCatalyst 13.0, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
        //      self.service?.bluetoothAuthorization =
        //        BluetoothAuthorization(
        //          cbManagerAuthorization: peripheral.authorization
        //        ) ?? .notDetermined
        //    }
        //    else if #available(OSX 10.13, iOS 9.0, *) {
        //      self.service?.bluetoothAuthorization =
        //        BluetoothAuthorization(
        //          cbPeripheralManagerAuthorizationStatus:
        //          CBPeripheralManager.authorizationStatus()
        //        ) ?? .notDetermined
        //    }
        self.stopPeripheralManager()
        switch peripheral.state {
            case .poweredOn:
                let service = CBMutableService.tcnPeripheralService
                if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    os_log(
                        "Peripheral manager adding service=%@",
                        log: .bluetooth,
                        service.description
                    )
                }
                peripheral.add(service)
            default:
                ()
        }
    }
    
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if let error = error {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral manager did add service=%@ error=%@",
                    log: .bluetooth,
                    type:.error,
                    service.description,
                    error as CVarArg
                )
            }
        }
        else {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral manager did add service=%@",
                    log: .bluetooth,
                    service.description
                )
            }
            self.startAdvertising()
        }
    }
    
    private func startAdvertising() {
        let advertisementData: [String : Any] = [
            CBAdvertisementDataServiceUUIDsKey : [CBUUID.tcnService],
            // iOS 13.4 (and older) does not support advertising service data
            // for third-party apps.
            // CBAdvertisementDataServiceDataKey : self.generateTCN()
        ]
        self.peripheralManager?.startAdvertising(advertisementData)
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Peripheral manager starting advertising advertisementData=%@",
                log: .bluetooth,
                advertisementData.description
            )
        }
    }
    
    func peripheralManagerDidStartAdvertising(
        _ peripheral: CBPeripheralManager,
        error: Error?
    ) {
        if let error = error {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral manager did start advertising error=%@",
                    log: .bluetooth,
                    type:.error,
                    error as CVarArg
                )
            }
        }
        else {
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral manager did start advertising",
                    log: .bluetooth
                )
            }
        }
    }
    
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Peripheral manager did receive read request=%@",
                log: .bluetooth,
                request.description
            )
        }
        
        let tcn = generateTCN()
        request.value = tcn
        
        peripheral.respond(to: request, withResult: .success)
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Peripheral manager did respond to read request with result=%d",
                log: .bluetooth,
                CBATTError.success.rawValue
            )
        }
    }
    
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
                "Peripheral manager did receive write requests=%@",
                log: .bluetooth,
                requests.description
            )
        }
        
        for request in requests {
            do {
                guard request.characteristic.uuid == .tcnCharacteristic else {
                    throw CBATTError(.requestNotSupported)
                }
                guard let value = request.value, value.count >= 16 else {
                    throw CBATTError(.invalidPdu)
                }
                let tcn = Data(value[0..<16])
                self.tcnsForRemoteDeviceIdentifiers[request.central.identifier] = tcn
                self.didFindTCN(tcn, estimatedDistance: self.estimatedDistancesForRemoteDeviceIdentifiers[request.central.identifier])
            }
            catch {
                var result = CBATTError.invalidPdu
                if let error = error as? CBATTError {
                    result = error.code
                }
                peripheral.respond(to: request, withResult: result)
                if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    os_log(
                        "Peripheral manager did respond to request=%@ with result=%d",
                        log: .bluetooth,
                        request.description,
                        result.rawValue
                    )
                }
                return
            }
        }
        
        if let request = requests.first {
            peripheral.respond(to: request, withResult: .success)
            if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                os_log(
                    "Peripheral manager did respond to request=%@ with result=%d",
                    log: .bluetooth,
                    request.description,
                    CBATTError.success.rawValue
                )
            }
        }
    }
}
