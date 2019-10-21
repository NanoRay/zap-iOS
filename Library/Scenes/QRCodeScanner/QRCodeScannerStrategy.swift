//
//  Zap
//
//  Created by Otto Suess on 25.04.18.
//  Copyright © 2018 Zap. All rights reserved.
//

import Foundation
import Lightning
import SwiftBTC
import SwiftLnd
import mantaswift

struct QRCodeScannerStrategyError: Error {
    let message: String
}

protocol QRCodeScannerStrategy {
    var title: String { get }
    var pasteButtonTitle: String { get }

    func viewControllerForAddress(address: String,
                                  mantaRequest: PaymentRequestMessage?,
                                  completion: @escaping (Result<UIViewController, QRCodeScannerStrategyError>) -> Void)
}

extension QRCodeScannerStrategy {
    func viewControllerForAddress(address: String,
                                  mantaRequest: PaymentRequestMessage? = nil,
                                  completion: @escaping (Result<UIViewController, QRCodeScannerStrategyError>) -> Void) {
        return viewControllerForAddress(address: address, mantaRequest: mantaRequest, completion: completion)
    }
}
