//
//  NativeAdContent.swift
//  On Board
//
//  A plain value type mirroring the asset set of a Google native advanced ad,
//  plus the seam that supplies one. Deliberately framework-free: `AdCard` renders
//  this, not a `GADNativeAd`, so the card is previewable, testable, and buildable
//  with no AdMob account, no ad unit ID, and no SDK on the render path.
//
//  When the loader lands it maps `GADNativeAd` onto this and nothing in the view
//  layer changes. Nullability here matches the SDK headers exactly — see the notes
//  on each property, because several of them are counter-intuitive.
//

import Foundation

/// The subset of a native ad we render. Field-for-field with `GADNativeAd`.
struct NativeAdContent: Equatable, Sendable, Identifiable {
    let id: UUID

    /// Policy says always render it; the SDK declares it nullable anyway. Kept
    /// non-optional here by making it the one field the loader must resolve — an
    /// ad without a headline is discarded rather than rendered half-empty.
    let headline: String

    /// `GADNativeAd.body` — frequently absent on app-install inventory.
    let body: String?

    /// `GADNativeAd.advertiser` — the advertiser's name or visible URL.
    let advertiser: String?

    /// `GADNativeAd.callToAction`. A *string*, not a button: we build the view,
    /// Google supplies the words and owns the tap. Absent on plenty of brand
    /// inventory, so the layout must not depend on it.
    let callToAction: String?

    /// True when `mediaContent` has something renderable.
    ///
    /// Note the trap this exists to avoid: `GADNativeAd.mediaContent` is declared
    /// **nonnull**, so branching on "is there media" the obvious way never fires and
    /// you render an empty box forever. The real signal is
    /// `aspectRatio > 0 || hasVideoContent` — `mainImage` is the nullable one.
    let hasMedia: Bool

    init(
        id: UUID = UUID(),
        headline: String,
        body: String? = nil,
        advertiser: String? = nil,
        callToAction: String? = nil,
        hasMedia: Bool = true
    ) {
        self.id = id
        self.headline = headline
        self.body = body
        self.advertiser = advertiser
        self.callToAction = callToAction
        self.hasMedia = hasMedia
    }
}

/// Supplies ads for promoted slots. Mirrors the app's other service seams
/// (`AuthService`, `BoardService`, `SubscriptionService`) so the real AdMob loader
/// drops in behind it without touching the feed or the card.
protocol NativeAdProvider: Sendable {
    /// Returns nil when the slot goes unfilled — a normal outcome, not an error.
    /// The caller renders the house promo rather than collapsing the slot.
    func loadAd() async -> NativeAdContent?
}

/// Stands in for AdMob until the loader exists. Cycles through a few shapes of
/// inventory — full, no body, no CTA, no media, and unfilled — because those are
/// the states the card actually has to survive, and a provider that only ever
/// returns a perfect ad hides every layout bug worth finding.
struct MockNativeAdProvider: NativeAdProvider {
    /// Set false to exercise the house-promo path exclusively.
    var fills: Bool = true

    func loadAd() async -> NativeAdContent? {
        try? await Task.sleep(for: .milliseconds(300))
        guard fills else { return nil }
        return Self.samples.randomElement()
    }

    static let samples: [NativeAdContent] = [
        NativeAdContent(
            headline: "Lumen Study — flashcards that actually stick",
            body: "Spaced repetition, past papers, and step-by-step solutions.",
            advertiser: "Lumen Labs",
            callToAction: "Install"
        ),
        // No body — common on app-install creative.
        NativeAdContent(
            headline: "Half off your first three rides this week",
            advertiser: "Kerb",
            callToAction: "Get offer"
        ),
        // No CTA — common on brand creative.
        NativeAdContent(
            headline: "The new Civic. Built for wherever you're headed.",
            body: "Efficient, quiet, and surprisingly roomy in the back.",
            advertiser: "Riverside Honda"
        ),
        // Long CTA — the string is the advertiser's choice, not ours.
        NativeAdContent(
            headline: "Apply now for fall housing",
            body: "Two blocks from campus. Tours running all week.",
            advertiser: "Vine Street Commons",
            callToAction: "Download the app today"
        ),
        // No media at all.
        NativeAdContent(
            headline: "Free tax filing for students",
            body: "Federal and state, no upsell.",
            advertiser: "Ledger",
            callToAction: "Start",
            hasMedia: false
        ),
    ]
}
