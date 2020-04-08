//
//  Created by Zsombor Szabo on 08/04/2020.
//

import Foundation

/// Errors related to the TCN protocol.
public enum TCNError: Error {
    
    /// An unknown memo type was encountered while parsing a report.
    case UnknownMemoType(UInt8)
    
    /// Reports cannot include the TCN with index 0.
    case InvalidReportIndex
        
    /// An underlying I/O error occurred while parsing data.
    case IO
    
    /// An oversized memo field was supplied when creating a report.
    case OversizeMemo(Int)
        
}
