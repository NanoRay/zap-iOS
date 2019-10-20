//
//  AsyncQueue.swift
//  mantaProtocolUI
//
//  Created by Alessandro Viganò on 05/09/2018.
//  Copyright © 2018 Alessandro Viganò. All rights reserved.
//

import Foundation
import Promises

class AsyncQueue<T> {
    var items = [T]()
    var promiseQueue = [Promise<T>]()
    
    func put (_ item: T) {
        items.append(item)
        if promiseQueue.count > 0 {
            promiseQueue.removeFirst().fulfill(items.removeFirst())
        }
    }
    
    func get () -> Promise<T> {
        if items.count > 0 {
            return Promise(items.removeFirst())
        }
        
        let promise = Promise<T>.pending()
        promiseQueue.append(promise)
        return promise
    }
}
