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

    /// App Store product page, used by the update prompts. The id matches
    /// `APP_STORE_ID` in the marketing site (onboard-web), which drives the
    /// auto-pulled changelog — keep the two in sync.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6782297168")!

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
