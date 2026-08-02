//
//  StoreKitSubscriptionService.swift
//  On Board
//
//  STUB — real StoreKit 2 lands in a later slice.
//
//  When implemented, this conforms to `SubscriptionService` by mapping
//  `StoreKit.Product` onto `FirstClassProduct`, driving purchases with the
//  imperative `product.purchase()` API (NOT SwiftUI's `SubscriptionStoreView`,
//  so the custom First Class design keeps full control), and reading
//  `Transaction.currentEntitlements` for the client-side entitlement. No server
//  mirror yet — the entitlement is local until ads exist (see the design spec).
//
//  Left unwired deliberately: `SubscriptionServiceFactory.make()` returns the
//  mock for now. Flip that factory to return this once a `.storekit` test
//  config and the real product identifiers are in place.
//

import Foundation

// Intentionally not yet conforming to `SubscriptionService` — this is a
// placeholder so the seam and the intended design are documented in code. Adding
// the conformance is the first step of the StoreKit slice.
enum StoreKitSubscriptionService {
    // TODO(first-class): implement SubscriptionService with StoreKit 2.
    //   - loadProducts(): Product.products(for: productIDs) -> map to FirstClassProduct
    //   - purchase(_:): Product.purchase(), verify Transaction, finish()
    //   - restore(): AppStore.sync() then re-read currentEntitlements
    //   - currentEntitlement(): scan Transaction.currentEntitlements for our ids
}
