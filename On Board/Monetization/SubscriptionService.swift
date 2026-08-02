//
//  SubscriptionService.swift
//  On Board
//
//  Protocol + factory for On Board First Class purchasing, mirroring the app's
//  other service seams (AuthService/OnboardingService). In this slice the
//  factory always returns the mock; the real StoreKit implementation lands in a
//  later slice behind the same protocol, so the UI never changes.
//

import Foundation

enum SubscriptionError: Error, Sendable, LocalizedError, PresentableDomainError {
    case productsUnavailable
    case purchaseFailed
    case restoreFoundNothing
    case unknown(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .productsUnavailable:
            String(localized: "First Class isn't available right now. Try again in a moment.")
        case .purchaseFailed:
            String(localized: "That purchase didn't go through.")
        case .restoreFoundNothing:
            String(localized: "We couldn't find a First Class subscription to restore.")
        case .unknown(let message):
            message
        }
    }

    nonisolated var recoverySuggestion: String? {
        switch self {
        case .productsUnavailable, .purchaseFailed:
            String(localized: "Check your connection and try again.")
        case .restoreFoundNothing:
            String(localized: "If you subscribed on another device, make sure you're signed in with the same Apple ID.")
        case .unknown:
            nil
        }
    }
}

/// Abstracts First Class purchasing. Every method is async and throwing so a
/// StoreKit implementation drops in later without changing callers.
protocol SubscriptionService: Sendable {
    /// The plans available to purchase.
    func loadProducts() async throws -> [FirstClassProduct]
    /// Attempt a purchase; returns the resulting entitlement state on success.
    func purchase(_ product: FirstClassProduct) async throws -> EntitlementState
    /// Restore a prior purchase; returns the resulting entitlement state.
    func restore() async throws -> EntitlementState
    /// The current entitlement without prompting the user (called on appear).
    func currentEntitlement() async -> EntitlementState
    /// DEV-only: forget a simulated purchase so the promo state can be re-entered.
    func devForgetEntitlement() async
}

extension SubscriptionService {
    /// No-op by default. A real StoreKit entitlement is Apple's to revoke, not
    /// ours — the shipping implementation must never pretend it can drop one, so
    /// only the mock overrides this.
    func devForgetEntitlement() async {}
}

enum SubscriptionServiceFactory {
    @MainActor
    static func make() -> any SubscriptionService {
        // TODO(first-class): return `StoreKitSubscriptionService` once real
        // StoreKit 2 + a `.storekit` test config exist. Unlike the other
        // factories this does NOT branch on `AppConfiguration.isSupabaseConfigured`
        // — StoreKit needs a StoreKit configuration, not Supabase, and the
        // entitlement is client-side only for now (see the design spec).
        MockSubscriptionService()
    }
}
