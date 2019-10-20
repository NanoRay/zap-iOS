//
//  File.swift
//  mantaProtocolUI
//
//  Created by Alessandro Viganò on 06/09/2018.
//  Copyright © 2018 Alessandro Viganò. All rights reserved.
//

//
//  Logger.swift
//  example
//
//  Created by Alessandro Viganò on 31/07/2018.
//  Copyright © 2018 Alessandro Viganò. All rights reserved.
//

import Foundation

#if SWIFTYBEAVER
import SwiftyBeaver
#endif

import SwiftSocket

public protocol LoggerServiceType {
    //static func setUpLogger(isEmulator: Bool)
    static func verbose(_ message: Any, _ file: String, _ function: String, line: Int)
    static func debug(_ message: Any, _ file: String, _ function: String, line: Int)
    static func info(_ message: Any, _ file: String, _ function: String, line: Int)
    static func warning(_ message: Any, _ file: String, _ function: String, line: Int)
    static func error(_ message: Any, _ file: String, _ function: String, line: Int)
    static func configure()
}

enum LogLevel: String {
    case verbose, debug, info, warning, error
}

public class ConsoleLogger: LoggerServiceType {
    public static func configure() {
        
    }
    
    static func log(_ level: LogLevel, message: Any, file: String, function: String, line: Int ) {
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        print ( "\(level.rawValue.uppercased()) \(filename).\(function):\(line) - \(message)")
    }
    
    public static func verbose(_ message: Any, _ file: String = #file,
                               _ function: String = #function, line: Int = #line) {
        log(.verbose, message: message, file: file, function: function, line: line)
    }
    
    public static func debug(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        log(.debug, message: message, file: file, function: function, line: line)
    }
    
    public static func info(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        log(.info, message: message, file: file, function: function, line: line)
    }
    
    public static func warning(_ message: Any, _ file: String = #file,
                               _ function: String = #function, line: Int = #line) {
        log(.warning, message: message, file: file, function: function, line: line)
    }
    
    public static func error(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        log(.error, message: message, file: file, function: function, line: line)
    }
}

#if SWIFTYBEAVER

public class SwiftyBeaverLogger: LoggerServiceType {
    
    private static let loggerLibrary = SwiftyBeaver.self
    
    public static func configure() {
        let console = ConsoleDestination()
        console.format = "$DHH:mm:ss.SSS$d $C$L$c $N.$F:$l - $M"
        loggerLibrary.addDestination(console)
        
    }
    
    public static func verbose(_ message: Any, _ file: String = #file,
                               _ function: String = #function, line: Int = #line) {
        loggerLibrary.verbose(message, file, function, line: line)
    }
    
    public static func debug(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        loggerLibrary.debug(message, file, function, line: line)
    }
    
    public static func info(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        loggerLibrary.info(message, file, function, line: line)
    }
    
    public static func warning(_ message: Any, _ file: String = #file,
                               _ function: String = #function, line: Int = #line) {
        loggerLibrary.warning(message, file, function, line: line)
    }
    
    public static func error(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        loggerLibrary.error(message, file, function, line: line)
    }
}
#endif

public class LogStashLogger: LoggerServiceType {
    private static var client: TCPClient?
    private static var buffer: [String] = []
    
    public static var extra: [String: Any] = [:]
    public static func configure() {
        
    }
    
    private static func connect() {
        guard let client = client else { return }
        if client.fd == nil {
            switch client.connect(timeout: 10) {
            case .success:
                while buffer.count > 0 {
                    send(buffer.removeFirst())
                }
            case .failure:
                print ("Error connecting")
                return
            }
        }
    }
    
    public static func configure(host: String, port: Int32, extra: [String: Any]=[:]) {
        client = TCPClient(address: host, port: port)
        self.extra = extra
    }
    
    static func send(_ jsonString: String) {
        guard let client = client else { return }
        
        connect()
        
        switch client.send(string: "\(jsonString)\n") {
        case .success:
            return
        case .failure:
            buffer.append(jsonString)
            connect()
        }
    }
    
    static func log(_ level: LogLevel, message: Any, file: String, function: String, line: Int ) {
        
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        
        var data = [ "level": level.rawValue.uppercased(),
                     "filename": filename,
                     "function": function,
                     "line": line,
                     "message": message]
        
        data.merge(extra) { (current, _) in current }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []) else { return }
        
        let jsonString: String = String(data: jsonData, encoding: .utf8)!
        
        send(jsonString)
        
    }
    
    public static func verbose(_ message: Any, _ file: String = #file,
                               _ function: String = #function, line: Int = #line) {
        log(.verbose, message: message, file: file, function: function, line: line)
    }
    
    public static func debug(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        log(.debug, message: message, file: file, function: function, line: line)
    }
    
    public static func info(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        log(.info, message: message, file: file, function: function, line: line)
    }
    
    public static func warning(_ message: Any, _ file: String = #file,
                               _ function: String = #function, line: Int = #line) {
        log(.warning, message: message, file: file, function: function, line: line)
    }
    
    public static func error(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        log(.error, message: message, file: file, function: function, line: line)
    }
}

public class MultipleLogger: LoggerServiceType {
    static private var loggers: [LoggerServiceType.Type] = []

    public static func info(_ message: Any, _ file: String, _ function: String, line: Int) {
        for logger in loggers {
            logger.info(message, file, function, line: line)
        }
    }
    
    public static func debug(_ message: Any, _ file: String, _ function: String, line: Int) {
        for logger in loggers {
            logger.debug(message, file, function, line: line)
        }
    }
    
    public static func verbose(_ message: Any, _ file: String, _ function: String, line: Int) {
        for logger in loggers {
            logger.verbose(message, file, function, line: line)
        }
    }
    
    public static func warning(_ message: Any, _ file: String, _ function: String, line: Int) {
        for logger in loggers {
            logger.warning(message, file, function, line: line)
        }
    }
    
    public static func configure(_ loggers: [LoggerServiceType.Type]) {
        self.loggers = loggers
    }
    
    public static func configure() {
        
    }
    
}

//Trick for using default parameters
extension LoggerServiceType {
    
    public static func debug(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        self.debug(message, file, function, line: line)
    }
    
    public static func info(_ message: Any, _ file: String = #file,
                            _ function: String = #function, line: Int = #line) {
        self.info (message, file, function, line: line)
    }
    
    public static func error(_ message: Any, _ file: String = #file,
                             _ function: String = #function, line: Int = #line) {
        self.error (message, file, function, line: line)
    }
}
