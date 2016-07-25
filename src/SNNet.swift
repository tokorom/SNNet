//
//  SNNet.swift
//  canvas
//
//  Created by satoshi on 11/23/15.
//  Copyright © 2015 Satoshi Nakajima. All rights reserved.
//

import UIKit

class SNNetError: NSObject, ErrorType {
    let res:NSHTTPURLResponse
    init(res:NSHTTPURLResponse) {
        self.res = res
    }

    var localizedDescription:String {
        // LAZY
        return self.description
    }
    
    override var description:String {
        let message:String
        switch(res.statusCode) {
        case 400:
            message = "Bad Request"
        case 401:
            message = "Unauthorized"
        case 402:
            message = "Payment Required"
        case 403:
            message = "Forbidden"
        case 404:
            message = "Not Found"
        case 405:
            message = "Method Not Allowed"
        case 406:
            message = "Proxy Authentication Required"
        case 407:
            message = "Request Timeout"
        case 408:
            message = "Request Timeout"
        case 409:
            message = "Conflict"
        case 410:
            message = "Gone"
        case 411:
            message = "Length Required"
        case 500:
            message = "Internal Server Error"
        case 501:
            message = "Not Implemented"
        case 502:
            message = "Bad Gateway"
        case 503:
            message = "Service Unavailable"
        case 504:
            message = "Gateway Timeout"
        default:
            message = "HTTP Error"
        }
        return "\(message) (\(res.statusCode))"
    }
}

class SNNet: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {
    static let boundary = "0xKhTmLbOuNdArY---This_Is_ThE_BoUnDaRyy---pqo"

    static let sharedInstance = SNNet()
    static let session:NSURLSession = {
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        return NSURLSession(configuration: config, delegate: SNNet.sharedInstance, delegateQueue: NSOperationQueue.mainQueue())
    }()
    static var apiRoot = NSURL(string: "https://www.google.com")!
    
    static func deleteAllCookiesForURL(url:NSURL) {
        let storage = NSHTTPCookieStorage.sharedHTTPCookieStorage()
        if let cookies = storage.cookiesForURL(url) {
            for cookie in cookies {
                storage.deleteCookie(cookie)
            }
        }
    }

    static func get(path:String, params:[String:String]? = nil, callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        return SNNet.request("GET", path: path, params:params, callback:callback)
    }

    static func post(path:String, params:[String:String]? = nil, callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        return SNNet.request("POST", path: path, params:params, callback:callback)
    }

    static func put(path:String, params:[String:String]? = nil, callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        return SNNet.request("PUT", path: path, params:params, callback:callback)
    }

    static func delete(path:String, params:[String:String]? = nil, callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        return SNNet.request("DELETE", path: path, params:params, callback:callback)
    }

    static func post(path:String, json:[String:AnyObject], params:[String:String], callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        do {
            let data = try NSJSONSerialization.dataWithJSONObject(json, options: NSJSONWritingOptions())
            return post(path, fileData: data, params: params, callback: callback)
        } catch {
            callback(url: nil, err: error)
            return nil
        }
    }

    static func post(path:String, file:NSURL, params:[String:String], callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        guard let data = NSData(contentsOfURL: file) else {
            // BUGBUG: callback with an error
            return nil
        }
        return post(path, fileData: data, params: params, callback: callback)
    }

    static func post(path:String, fileData:NSData, params:[String:String], callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        guard let url = urlFromPath(path) else {
            print("SNNet Invalid URL:\(path)")
            // BUGBUG: callback with an error
            return nil
        }
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"

        var body = ""
        for (name, value) in params {
            body += "\r\n--\(boundary)\r\n"
            body += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            body += value
        }
        body += "\r\n--\(boundary)\r\n"
        body += "Content-Disposition: form-data; name=\"file\"\r\n\r\n"
        
        //print("SNNet FILE body:\(body)")

        let data = NSMutableData(data: body.dataUsingEncoding(NSUTF8StringEncoding)!)

        data.appendData(fileData)
        data.appendData("\r\n--\(boundary)--\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        
        request.HTTPBody = data
        request.setValue("\(data.length)", forHTTPHeaderField: "Content-Length")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        return sendRequest(request, callback: callback)
    }
    
    private static let regex = try! NSRegularExpression(pattern: "^https?:", options: NSRegularExpressionOptions())
    
    private static func urlFromPath(path:String) -> NSURL? {
        if regex.matchesInString(path, options: NSMatchingOptions(), range: NSMakeRange(0, path.characters.count)).count > 0 {
            return NSURL(string: path)!
        }
        return apiRoot.URLByAppendingPathComponent(path)
    }
    
    private static func request(method:String, path:String, params:[String:String]? = nil, callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask? {
        guard let url = urlFromPath(path) else {
            print("SNNet Invalid URL:\(path)")
            return nil
        }
        var query:String?
        if let p = params {
            let components = NSURLComponents(string: "http://foo")!
            components.queryItems = p.map({ (key:String, value:String?) -> NSURLQueryItem in
                return NSURLQueryItem(name: key, value: value)
            })
            if let urlQuery = components.URL {
                query = urlQuery.query
            }
        }
        
        let request:NSMutableURLRequest
        if let q = query where method == "GET" {
            let urlGet = NSURL(string: url.absoluteString + "?\(q)")!
            request = NSMutableURLRequest(URL: urlGet)
            print("SNNet \(method) url=\(urlGet.absoluteString)")
        } else {
            request = NSMutableURLRequest(URL: url)
            print("SNNet \(method) url=\(url.absoluteString) +\(query)")
        }

        request.HTTPMethod = method
        if let data = query?.dataUsingEncoding(NSUTF8StringEncoding) where method != "GET" {
            request.HTTPBody = data
            request.setValue("\(data.length)", forHTTPHeaderField: "Content-Length")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return sendRequest(request, callback: callback)
    }

    private static func sendRequest(request:NSURLRequest, callback:(url:NSURL?, err:ErrorType?)->(Void)) -> NSURLSessionDownloadTask {
        let task = session.downloadTaskWithRequest(request) { (url:NSURL?, res:NSURLResponse?, err:NSError?) -> Void in
            if let error = err {
                print("SNNet ### error=\(error)")
                callback(url: url, err: err)
            } else {
                guard let hres = res as? NSHTTPURLResponse else {
                    print("SNNet ### not HTTP Response=\(res)")
                    // NOTE: Probably never happens
                    return
                }
                if (200..<300).contains(hres.statusCode) {
                    callback(url: url, err: nil)
                } else {
                    callback(url: url, err: SNNetError(res: hres))
                }
            }
        }
        task.resume()
        return task
    }
    
    static let didSentBytes = "didSentBytes"
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        NSNotificationCenter.defaultCenter().postNotificationName(SNNet.didSentBytes, object: task)
    }
}
