//
//  MantaWallet.swift
//  mantaprotocol
//
//  Created by Alessandro Viganò on 23/07/2018.
//  Copyright © 2018 Alessandro Viganò. All rights reserved.
//

import Foundation
import CocoaMQTT
import Promises

enum MantaError: Error {
    case jsonError
    
}

extension String {
    func substring(with nsrange: NSRange) -> Substring? {
        guard let range = Range(nsrange, in: self) else { return nil }
        return self[range]
    }
}

extension String {
    func capturedGroups(withRegex pattern: String) -> [String] {
        var results = [String]()
        
        var regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return results
        }
        
        let matches = regex.matches(in: self, options: [], range: NSRange(self.startIndex..., in: self))
        
        guard let match = matches.first else { return results }
        
        let lastRangeIndex = match.numberOfRanges - 1
        guard lastRangeIndex >= 1 else { return results }
        
        for idx in 1...lastRangeIndex {
            let capturedGroupIndex = match.range(at: idx)
            //let matchedString = (self as NSString).substring(with:capturedGroupIndex)
            if let matchedString = self.substring(with: capturedGroupIndex) {
                results.append(String(matchedString))
            }
        }
        
        return results
    }
}

// swiftlint:disable identifier_name

class MQTTDelegate: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics topics: [String]) {
        
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        
    }
    
    weak var manta: MantaWallet?
    
    init (_ manta: MantaWallet) {
        self.manta = manta
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        guard let manta = manta else {return}
        manta.connectPromise?.fulfill(())
        manta.log.info("Connected to MQTT Broker with id \(manta.clientID))")
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        manta?.log.debug("Got publish ack")
        
        guard let promise = manta?.pubACKPromises[Int(id)] else {return}
        
        manta?.pubACKPromises[Int(id)] = nil
        promise.fulfill(())
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let tokens = message.topic.split(separator: "/")
        manta?.log.debug("Got \(message.string!) on \(message.topic)")
        
        switch tokens[0] {
        case "payment_requests":
            
            let jsonDecoder = JSONDecoder()
            let sessionID = tokens[1]
            
            do {
                let paymentRequestEnvelope =
                    try jsonDecoder.decode(PaymentRequestEnvelope.self, from: Data(bytes: message.payload))
                manta?.paymentRequestEnvelope = paymentRequestEnvelope
                
                manta?.log.info("Got Payment Request for sessionID \(sessionID)")
                
                manta?.getPaymentPromise?.fulfill(paymentRequestEnvelope)
            } catch {
                manta?.log.error("Error in parsing payment request")
            }
        case "acks":
            let sessionID = tokens[1]
            
            do {
                let ackMessage = try AckMessage.decode(data: (message.string?.data(using: .utf8))!)
                manta?.log.info("""
                    Got Ack - Status: \(ackMessage.status) TXID: \(ackMessage.txid) SessionID \(sessionID)
                    """)
                manta?.acks.put(ackMessage)
            } catch {
                manta?.log.error("Error in parsing payment request")
            }
            
        default:
            manta?.log.error("Unknown message")
        }
        
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        
    }
    
    public func mqttDidPing(_ mqtt: CocoaMQTT) {
        
    }
    
    public func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        
    }
    
    public func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        guard let manta = manta else {return}
        manta.log.info("Client \(manta.clientID) got Disconnected")
        
    }
}

// swiftlint:enable identifier_name

// MARK: -

public class MantaWallet {
    var mqtt: CocoaMQTT
    var sessionID: String
    var paymentRequestEnvelope: PaymentRequestEnvelope?
    let port: Int
    let host: String
    let acks = AsyncQueue<AckMessage>()
    let clientID = NSUUID().uuidString
    // swiftlint:disable weak_delegate
    var delegate: CocoaMQTTDelegate?
    // swiftlint:enable weak_delegate
    
    var connectPromise: Promise<Void>?
    var pubACKPromises: [Int: Promise<Void>] = [:]
    var getPaymentPromise: Promise<PaymentRequestEnvelope>?
    
    let log: LoggerServiceType.Type
    
    public static func parseURL (_ url: String) -> [String] {
        let pattern = "^manta:\\/\\/((?:\\w|\\.)+)(?::(\\d+))?\\/(.+)$"
        return url.capturedGroups(withRegex: pattern)
    }
    
    init? (_ url: String, mqtt: CocoaMQTT? = nil, logger: LoggerServiceType.Type? = nil) {
        
        let results = MantaWallet.parseURL(url)
        
        if results.count < 2 { return nil}
        
        self.log = logger ?? ConsoleLogger.self
        self.host = results[0]
        self.sessionID = results[results.count-1]
        self.port = results.count == 3 ? Int(results[1])! : 1883
        
        self.mqtt = mqtt != nil ? mqtt! : CocoaMQTT(clientID: clientID, host: host, port: UInt16(port))
        
        // Keep a reference for arc
        self.delegate = MQTTDelegate(self)
        self.mqtt.delegate = self.delegate
        self.mqtt.autoReconnect = true
        
        log.configure()
    }
    
    convenience public init? (_ url: String, logger: LoggerServiceType.Type? = nil) {
        self.init(url, mqtt: nil, logger: logger)
    }
    
    deinit {
        mqtt.disconnect()
    }
    
    func connect () -> Promise <Void> {
        if mqtt.connState == .connected {return Promise(())}
        
        mqtt.connect()
        connectPromise = Promise<Void>.pending()
        
        return connectPromise!
        
    }
    
    func publish(_ topic: String, withString: String) -> Promise <Void> {
        let id = mqtt.publish(topic, withString: withString)
        pubACKPromises[id] = Promise<Void>.pending()
        return pubACKPromises[id]!
    }
    
    public func getPaymentRequest(cryptoCurrency: String = "all") -> Promise <PaymentRequestEnvelope> {
        
        connect().then {
            self.mqtt.subscribe("payment_requests/\(self.sessionID)")
            self.mqtt.publish("payment_requests/\(self.sessionID)/\(cryptoCurrency)", withString: "")
        }
        
        getPaymentPromise = Promise<PaymentRequestEnvelope>.pending()
        
        return getPaymentPromise!
        
    }
    
    public func sendPayment_(cryptoCurrency: String, hashes: String) -> Promise <Void> {
        let jsonEncoder = JSONEncoder()
        let paymentMessage = PaymentMessage (cryptoCurrency: cryptoCurrency, transactionHash: hashes)
        guard let jsonData = try? jsonEncoder.encode(paymentMessage) else { return Promise(MantaError.jsonError) }
        
        mqtt.subscribe("acks/\(self.sessionID)")
        
        log.info("Sending payment with hash: \(hashes) crypto: \(cryptoCurrency)")
        
        return publish("payments/\(self.sessionID)", withString: String(data: jsonData, encoding: .utf8)!)
        // mqtt.publish("payments/\(self.sessionID)", withString: String(data: jsonData, encoding: .utf8)!)
    }
    
}
