//
//  Messages.swift
//  mantaTests
//
//  Created by Alessandro Viganò on 04/09/2018.
//  Copyright © 2018 Alessandro Viganò. All rights reserved.
//

import Foundation

// MARK: - Crypto Functions
func getCertificate(fromPEM: String) -> SecCertificate? {
    let base64 = fromPEM.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
        .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
    guard let data = NSData(base64Encoded: base64, options: NSData.Base64DecodingOptions.ignoreUnknownCharacters) else {
        return nil
    }
    return SecCertificateCreateWithData(kCFAllocatorDefault, data)
}

func verifyChain (testCer: SecCertificate, CACer: SecCertificate) -> SecTrustResultType {
    var trust: SecTrust?
    var result = SecTrustResultType.invalid
    
    let certs = [testCer, CACer] as CFArray
    SecTrustCreateWithCertificates(certs, SecPolicyCreateSSL(false, nil), &trust)
    SecTrustSetAnchorCertificates(trust!, [CACer] as CFArray)
    
    SecTrustEvaluate(trust!, &result)
    
    return result
}

func getPublicKey(from: String) -> SecKey? {
    guard let cer = getCertificate(fromPEM: from) else {
        return nil
    }
    
    return getPublicKey(from: cer)
}

func getPublicKey(from: SecCertificate) -> SecKey? {
    var key: SecKey?
    #if os(OSX)
    SecCertificateCopyPublicKey(from, &key)
    #elseif os(iOS)
    key = SecCertificateCopyPublicKey(from)
    #endif
    
    return key
}

func verifySignature (key: SecKey, message: String, signature: String) -> Bool {
    return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                 message.data(using: .utf8)! as CFData, NSData(base64Encoded: signature)!, nil)
}

func verifySignatureExtended (CACer: String, ppCer: String, message: String, signature: String) -> Bool {
    guard let cauth = getCertificate(fromPEM: CACer), let test = getCertificate(fromPEM: ppCer) else {
        return false
    }
    
    if verifyChain(testCer: test, CACer: cauth) != .unspecified {
        return false
    }
    
    guard let key = getPublicKey(from: test) else {
        return false
    }
    
    return verifySignature(key: key, message: message, signature: signature)
    
}

// MARK: - Messages
public enum Status: String, Codable {
    case NEW = "new"
    case PENDING = "pending"
    case PAID = "paid"
}

public struct AckMessage: Codable {
    public let txid: String
    public let status: Status
    public let url: String?
    public let amount: Decimal?
    public let transactionHash: String?
    
    enum CodingKeys: String, CodingKey {
        case txid
        case status
        case url
        case amount
        case transactionHash = "transaction_hash"
    }
    
}

public struct Destination: Codable {
    public let amount: Decimal
    public let cryptoCurrency: String
    public let destinationAddress: String
    
    enum CodingKeys: String, CodingKey {
        case amount
        case cryptoCurrency = "crypto_currency"
        case destinationAddress = "destination_address"
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        amount = Decimal(string: try values.decode(String.self, forKey: .amount)) ?? Decimal(0)
        cryptoCurrency = try values.decode(String.self, forKey: .cryptoCurrency)
        destinationAddress = try values.decode(String.self, forKey: .destinationAddress)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount.description, forKey: .amount)
        try container.encode(cryptoCurrency, forKey: .cryptoCurrency)
        try container.encode(destinationAddress, forKey: .cryptoCurrency)
    }
}

public struct Merchant: Codable {
    public let name: String
    public let address: String?
}

extension Merchant: Equatable {
    public static func == (lhs: Merchant, rhs: Merchant) -> Bool {
        return
            lhs.name == rhs.name && lhs.address == rhs.address
    }
}

/// Prova
public struct PaymentRequestMessage: Codable {
    public let amount: Decimal
    public let fiatCurrency: String
    public let destinations: [Destination]
    public let merchant: Merchant
    public let supportedCryptos: [String]
    
    enum CodingKeys: String, CodingKey {
        case amount
        case fiatCurrency = "fiat_currency"
        case destinations
        case merchant
        case supportedCryptos = "supported_cryptos"
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        amount = Decimal(string: try values.decode(String.self, forKey: .amount)) ?? Decimal(0)
        fiatCurrency = try values.decode(String.self, forKey: .fiatCurrency)
        destinations = try values.decode([Destination].self, forKey: .destinations)
        merchant = try values.decode(Merchant.self, forKey: .merchant)
        supportedCryptos = try values.decode([String].self, forKey: .supportedCryptos)
    }
}

extension PaymentRequestMessage: Equatable {
    public static func == (lhs: PaymentRequestMessage, rhs: PaymentRequestMessage) -> Bool {
        return
            lhs.amount == rhs.amount &&
                lhs.fiatCurrency == rhs.fiatCurrency &&
                lhs.merchant == rhs.merchant &&
                lhs.supportedCryptos == rhs.supportedCryptos
    }
}

public struct PaymentRequestEnvelope: Codable {
    public let message: String
    public let signature: String
    
    public func unpack() throws -> PaymentRequestMessage {
        let jsonDecoder = JSONDecoder()
        return try jsonDecoder.decode(PaymentRequestMessage.self, from: message.data(using: .utf8)!)
    }
    
    public func verify(_ pem: String, withCA caPEM: String) -> Bool {
        return verifySignatureExtended(CACer: caPEM, ppCer: pem, message: self.message, signature: self.signature)
    }
}

public struct PaymentMessage: Codable {
    let cryptoCurrency: String
    let transactionHash: String
    
    enum CodingKeys: String, CodingKey {
        case cryptoCurrency = "crypto_currency"
        case transactionHash = "transaction_hash"
    }
}

public extension Decodable {
    static func decode(data: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }
}

public extension Encodable {
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(self)
    }
}
