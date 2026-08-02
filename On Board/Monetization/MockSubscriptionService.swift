//
//  MockSubscriptionService.swift
//  On Board
//
//  Drives the First Class UI with no StoreKit configuration. Simulates loading,
//  purchasing, and restoring, and persists a "subscribed" flag to UserDefaults
//  *for dev only* so the subscribed UI survives an app relaunch in mock mode.
//  A `simulateFailure` switch exercises the error path in tests.
//

import Foundation

final class MockSubscriptionService: SubscriptionService, @unchecked Sendable {
    private let defaults: UserDefaults
    private let subscribedKey = "mock.firstclass.subscribed"
    private let simulateFailure: Bool

    init(defaults: UserDefaults = .standard, simulateFailure: Bool = false) {
        self.defaults = defaults
        self.simulateFailure = simulateFailure
    }

    func loadProducts() async throws -> [FirstClassProduct] {
        try await Task.sleep(for: .milliseconds(250))
        if simulateFailure { throw SubscriptionError.productsUnavailable }
        return Self.sampleProducts
    }

    func purchase(_ product: FirstClassProduct) async throws -> EntitlementState {
        try await Task.sleep(for: .milliseconds(650))
        if simulateFailure { throw SubscriptionError.purchaseFailed }
        defaults.set(true, forKey: subscribedKey)
        return .subscribed(renewalNote: Self.renewalNote(for: product.plan))
    }

    func restore() async throws -> EntitlementState {
        try await Task.sleep(for: .milliseconds(400))
        if simulateFailure { throw SubscriptionError.restoreFoundNothing }
        defaults.set(true, forKey: subscribedKey)
        return .subscribed(renewalNote: nil)
    }

    func currentEntitlement() async -> EntitlementState {
        if defaults.bool(forKey: subscribedKey) {
            return .subscribed(renewalNote: nil)
        }
        return .loaded(products: Self.sampleProducts)
    }

    /// Test/dev helper: forget the persisted mock subscription.
    func resetForTesting() {
        defaults.removeObject(forKey: subscribedKey)
    }

    func devForgetEntitlement() async {
        resetForTesting()
    }

    // MARK: - Sample data (placeholder prices; real values come from App Store Connect)

    static let sampleProducts: [FirstClassProduct] = [
        FirstClassProduct(
            id: "onboard.firstclass.monthly",
            plan: .monthly,
            displayPrice: "$2.99",
            pricePeriod: "/mo",
            hasIntroTrial: true,
            trialDescription: "7 days free"
        ),
        FirstClassProduct(
            id: "onboard.firstclass.yearly",
            plan: .yearly,
            displayPrice: "$19.99",
            pricePeriod: "/yr",
            hasIntroTrial: true,
            trialDescription: "7 days free",
            isBestValue: true
        ),
    ]

    private static func renewalNote(for plan: FirstClassPlan) -> String {
        switch plan {
        case .monthly: String(localized: "Renews monthly")
        case .yearly: String(localized: "Renews yearly")
        }
    }
}
