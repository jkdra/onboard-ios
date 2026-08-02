//
//  FirstClassModels.swift
//  On Board
//
//  Value types for On Board First Class — the premium subscription. These carry
//  no billing logic; they describe what the UI renders and what the entitlement
//  layer tracks. See docs/superpowers/specs/2026-07-29-first-class-subscription-shell-design.md
//

import Foundation

/// The two subscription cadences offered.
enum FirstClassPlan: String, Sendable, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }
}

/// A purchasable First Class product. In this slice these come from the mock;
/// later, a StoreKit-backed service maps `StoreKit.Product` onto this shape so
/// the UI never learns the difference.
struct FirstClassProduct: Identifiable, Sendable, Equatable {
    /// Product identifier (mock string now; StoreKit product id later).
    let id: String
    let plan: FirstClassPlan
    /// Localized price, e.g. "$2.99". Placeholder in mock; real value from
    /// App Store Connect later.
    let displayPrice: String
    /// Short period suffix shown next to the price, e.g. "/mo", "/yr".
    let pricePeriod: String
    let hasIntroTrial: Bool
    /// Human phrase for the intro offer, e.g. "7 days free".
    let trialDescription: String?
    /// Flags the plan we want to nudge toward (rendered as a "Best value" badge).
    var isBestValue: Bool = false
}

/// Whether a perk is live or teased as upcoming ("Peek" is scaffolding-only).
enum PerkAvailability: Sendable {
    case available
    case comingSoon
}

/// One line item in the "what you get" list. Data-driven so adding a perk later
/// is data, not a new view.
struct FirstClassPerk: Identifiable, Sendable {
    let symbol: String   // SF Symbol name
    let title: String
    let blurb: String
    let availability: PerkAvailability

    var id: String { title }
}

extension FirstClassPerk {
    /// The perks advertised on the First Class screen. Only `Peek` is
    /// `.comingSoon` for now; the rest are the promised (not-yet-wired) unlocks.
    static let advertised: [FirstClassPerk] = [
        FirstClassPerk(
            symbol: "hand.raised.slash.fill",
            title: "Ad-Free",
            blurb: "No promoted ads. Sponsored posts from local spots still stay — they're part of campus.",
            availability: .available
        ),
        FirstClassPerk(
            symbol: "paintpalette.fill",
            title: "Profile Colors",
            blurb: "Tint your profile with a palette only First Class unlocks.",
            availability: .available
        ),
        FirstClassPerk(
            symbol: "circle.dashed",
            title: "Custom Crop Shapes",
            blurb: "Shape your profile photo beyond the circle.",
            availability: .available
        ),
        FirstClassPerk(
            symbol: "textformat.alt",
            title: "Post Fonts",
            blurb: "Give your posts a voice with fonts no one else has.",
            availability: .available
        ),
        FirstClassPerk(
            symbol: "sparkles",
            title: "Early Access",
            blurb: "Try new features before they reach the rest of the board.",
            availability: .available
        ),
        FirstClassPerk(
            symbol: "bolt.heart.fill",
            title: "Priority Support",
            blurb: "Jump the line whenever you need a hand.",
            availability: .available
        ),
        FirstClassPerk(
            symbol: "binoculars.fill",
            title: "Peek",
            blurb: "Glimpse what's happening on nearby campus boards.",
            availability: .comingSoon
        ),
    ]
}

/// The entitlement/purchase state the paywall renders against.
enum EntitlementState: Sendable, Equatable {
    case loading
    case loaded(products: [FirstClassProduct])
    case purchasing
    case subscribed(renewalNote: String?)
    case failed
}
