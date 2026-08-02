//
//  EntitlementStore.swift
//  On Board
//
//  Tracks whether the signed-in user has On Board First Class, and drives the
//  paywall's purchase/restore flow. `isFirstClass` is the SINGLE gate every
//  future perk (ad removal, profile colors, custom crops, post fonts, …) reads —
//  nothing else should re-derive subscription status.
//
//  Client-side only for now: no server mirror. See the design spec.
//

import Foundation
import Observation

@Observable
@MainActor
final class EntitlementStore {
    private let service: any SubscriptionService

    /// The one gate future perks read.
    private(set) var isFirstClass = false
    /// What the paywall renders against.
    private(set) var state: EntitlementState = .loading
    /// Available plans (kept even while subscribed so the UI can reference them).
    private(set) var products: [FirstClassProduct] = []
    /// Surfaced through `.presentableErrorAlert`. A failed purchase/restore never
    /// fails silently.
    var alertError: PresentableAlertError?

    init(service: any SubscriptionService) {
        self.service = service
    }

    /// Called on First Class screen appear. Reads the current entitlement without
    /// prompting, then loads products if not already subscribed.
    func refresh() async {
        let current = await service.currentEntitlement()
        apply(current)
        if !isFirstClass {
            await loadProducts()
        }
    }

    func loadProducts() async {
        state = .loading
        do {
            let loaded = try await service.loadProducts()
            products = loaded
            if !isFirstClass {
                state = .loaded(products: loaded)
            }
        } catch {
            state = .failed
            alertError = PresentableAlertError.from(error)
        }
    }

    func purchase(_ product: FirstClassProduct) async {
        // Ignore a double-tap while a purchase is already resolving.
        guard state != .purchasing else { return }
        state = .purchasing
        do {
            let result = try await service.purchase(product)
            apply(result)
        } catch {
            // Roll back to the plan list and surface the failure.
            state = .loaded(products: products)
            alertError = PresentableAlertError.from(error)
        }
    }

    func restore() async {
        do {
            let result = try await service.restore()
            apply(result)
        } catch {
            alertError = PresentableAlertError.from(error)
        }
    }

    /// DEV-only: drop the simulated entitlement and return to the promo state, so
    /// the paywall can be walked repeatedly without deleting the app. Routed through
    /// the service (rather than just clearing `isFirstClass`) so the mock's persisted
    /// flag goes too — otherwise the next `refresh()` would restore membership.
    ///
    /// Safe against the real implementation: `devForgetEntitlement` defaults to a
    /// no-op, so this can't fake-revoke a genuine StoreKit purchase.
    func devRevertToFree() async {
        await service.devForgetEntitlement()
        await refresh()
    }

    private func apply(_ newState: EntitlementState) {
        state = newState
        switch newState {
        case .subscribed:
            isFirstClass = true
        case .loaded(let loaded):
            products = loaded
            isFirstClass = false
        case .loading, .purchasing, .failed:
            break
        }
    }
}
