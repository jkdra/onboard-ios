//
//  AppLinks.swift
//  On Board
//

import Foundation

enum AppLinks {
    static let supportEmail = "support@onboardapp.org"

    /// Legal pages live on the marketing site (web/ — `app/privacy`, `app/terms`).
    static let privacyPolicyURL = URL(string: "https://onboardapp.org/privacy")!
    static let termsOfServiceURL = URL(string: "https://onboardapp.org/terms")!

    static var reportMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "On Board — Report")
        ]
        return components.url ?? contactSupportMailURL
    }

    static var contactSupportMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        return components.url ?? URL(string: "mailto:\(supportEmail)")!
    }
}
