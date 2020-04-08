//
//  Created by Zsombor Szabo on 04/04/2020.
//

import Foundation
import CoreBluetooth

extension Double {
    
    public static let measuredRSSIAtOneMeterDefault: Double = -57
    
}

/// Returns the measured RSSI at 1 meter based on the Tx power level extracted from the advertisement
/// data and empirical measurements.
///   - advertisementData: The advertisement data from where to extract the Tx power level.
///   - hintIsAndroid: A hint whether the remote device is an Android one.
/// - Returns: The measured RSSI at 1 meter.
func getMeasuredRSSIAtOneMeter(
    advertisementData: [String : Any],
    hintIsAndroid: Bool = false) -> Double {
    
    var txPowerLevel: Int! =
        (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?
            .intValue
    
    if txPowerLevel == nil {
        // iOS 12 devices do not advertise the Tx power level.
        // Based on measurements, they seem to advertise at Tx power level 11.
        txPowerLevel = !hintIsAndroid ? 11 : 12
    }
    
    // Tx power levels are between -3 and 20. https://en.wikipedia.org/wiki/Bluetooth#Uses
    // Android clients report negative values, ones way below -3.
    // Based on measurements, they mean they are transmitting at
    // 20 - abs(txPowerLevel).
    if txPowerLevel < 0 {
        txPowerLevel = 20 + txPowerLevel
    }
    
    // Values determined by averaging the measurements between an iPhone X
    // MQAC2RM/A, an iPad (5th generation) MP2F2HC/A, and a Google Nexus 4
    // (MP1.0), the latter advertising at different Tx power levels.
    switch txPowerLevel! {
        case 12...20:
            return .measuredRSSIAtOneMeterDefault
        case 9..<12:
            return -71
        default:
            return -86
    }
}


/// Returns the estimated distance in meters based on the RSSI, measured RSSI at 1 meter, and
/// environmental factor.
///
/// https://iotandelectronics.wordpress.com/2016/10/07/how-to-calculate-distance-from-the-rssi-value-of-the-ble-beacon/
///
/// - Parameters:
///   - RSSI: The RSSI.
///   - measuredRSSIAtOneMeter: The measured RSSI at 1 meter.
///   - environmentalFactor: The environmental factor. Its range is between 2.0-4.0.
/// - Returns: The estimated distance in meters. -1, if the input is invalid.
func getEstimatedDistanceMeters(
    RSSI: Double,
    measuredRSSIAtOneMeter: Double = .measuredRSSIAtOneMeterDefault,
    environmentalFactor: Double = 2) -> Double {
    
    // Ensure input is valid
    guard RSSI < 20 else {
        return -1
    }
    guard environmentalFactor >= 2 && environmentalFactor <= 4 else {
        return -1
    }
    
    return pow(10, (measuredRSSIAtOneMeter - RSSI) / (10 * environmentalFactor))
}
