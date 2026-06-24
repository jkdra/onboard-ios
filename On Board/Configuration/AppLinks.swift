//
//  AppLinks.swift
//  On Board
//

import Foundation

enum AppLinks {
    static let supportEmail = "support@onboardapp.org"

    static var reportMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "On Board — Report")
        ]
        return components.url ?? URL(string: "mailto:\(supportEmail)")!
    }
}
