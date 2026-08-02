//
//  FirstClassTests.swift
//  On BoardTests
//
//  Covers the On Board First Class subscription shell against the mock service.
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct FirstClassTests {
    /// A throwaway UserDefaults so the mock's persisted "subscribed" flag never
    /// touches the real domain or leaks between tests.
    private func isolatedDefaults() -> UserDefaults {
        let suite = "test.firstclass.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - MockSubscriptionService

    @Test func loadsExactlyMonthlyAndYearlyBothWithTrial() async throws {
        let service = MockSubscriptionService(defaults: isolatedDefaults())
        let products = try await service.loadProducts()

        #expect(products.count == 2)
        #expect(products.contains { $0.plan == .monthly })
        #expect(products.contains { $0.plan == .yearly })
        #expect(products.allSatisfy { $0.hasIntroTrial })
        // Exactly one plan is flagged as the value anchor.
        #expect(products.filter(\.isBestValue).count == 1)
    }

    @Test func purchaseReportsSubscribedWithRenewalNote() async throws {
        let service = MockSubscriptionService(defaults: isolatedDefaults())
        let monthly = MockSubscriptionService.sampleProducts.first { $0.plan == .monthly }!

        let state = try await service.purchase(monthly)

        guard case .subscribed(let note) = state else {
            Issue.record("Expected .subscribed, got \(state)")
            return
        }
        #expect(note != nil)
        // Now persisted, so a fresh entitlement read is subscribed.
        if case .subscribed = await service.currentEntitlement() {} else {
            Issue.record("currentEntitlement should be .subscribed after purchase")
        }
    }

    @Test func restoreReportsSubscribed() async throws {
        let service = MockSubscriptionService(defaults: isolatedDefaults())
        let state = try await service.restore()
        if case .subscribed = state {} else {
            Issue.record("Expected .subscribed from restore, got \(state)")
        }
    }

    @Test func failureThrowsAndLeavesUserUnsubscribed() async throws {
        let defaults = isolatedDefaults()
        let service = MockSubscriptionService(defaults: defaults, simulateFailure: true)

        await #expect(throws: SubscriptionError.self) {
            _ = try await service.purchase(MockSubscriptionService.sampleProducts[0])
        }
        // A failed purchase must not have flipped the entitlement.
        if case .subscribed = await service.currentEntitlement() {
            Issue.record("A failed purchase must not leave the user subscribed")
        }
    }

    // MARK: - EntitlementStore

    @Test func storeStartsUnsubscribedAndLoadsProducts() async {
        let store = EntitlementStore(service: MockSubscriptionService(defaults: isolatedDefaults()))
        await store.refresh()

        #expect(store.isFirstClass == false)
        #expect(store.products.count == 2)
        #expect(store.state == .loaded(products: MockSubscriptionService.sampleProducts))
    }

    @Test func storeBecomesFirstClassAfterPurchase() async {
        let store = EntitlementStore(service: MockSubscriptionService(defaults: isolatedDefaults()))
        await store.refresh()
        await store.purchase(MockSubscriptionService.sampleProducts.first { $0.plan == .yearly }!)

        #expect(store.isFirstClass)
        if case .subscribed = store.state {} else {
            Issue.record("Store state should be .subscribed after purchase")
        }
        #expect(store.alertError == nil)
    }

    @Test func storeSurfacesAlertOnFailedPurchase() async {
        let store = EntitlementStore(service: MockSubscriptionService(defaults: isolatedDefaults(), simulateFailure: true))
        // Load products directly (loadProducts also fails here) then attempt purchase.
        await store.purchase(MockSubscriptionService.sampleProducts[0])

        #expect(store.isFirstClass == false)
        #expect(store.alertError != nil)
    }

    // MARK: - AdsGateway

    @Test func adsGatewayEligibleUntilFirstClass() async {
        let store = EntitlementStore(service: MockSubscriptionService(defaults: isolatedDefaults()))
        let ads = AdsGateway(entitlement: store)

        #expect(ads.isEligibleForAds)

        await store.purchase(MockSubscriptionService.sampleProducts.first { $0.plan == .yearly }!)

        #expect(store.isFirstClass)
        #expect(ads.isEligibleForAds == false)
    }

    // MARK: - ProfileColor (Profile Colors perk)

    @Test func profileColorNoneRendersAsDefaultRing() {
        #expect(ProfileColor.none.color == nil)
    }

    @Test func everyOtherProfileColorHasAColor() {
        for option in ProfileColor.allCases where option != .none {
            #expect(option.color != nil)
        }
    }
}
