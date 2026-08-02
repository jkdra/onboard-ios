//
//  AdsGateway.swift
//  On Board
//
//  The single gate every future ad-serving call site must check before
//  loading or showing a Google AdMob ad. On Board First Class's "Ad-Free"
//  perk is enforced HERE, once, rather than scattered across call sites —
//  one gate to audit, one place the ATT/consent flow eventually attaches to.
//
//  Sponsored posts (paid local-business placements) are NOT gated by this —
//  they're kept even for First Class members (see FirstClassPerk.advertised's
//  "Ad-Free" blurb) and are a separate mechanism with no AdMob/SDK involvement.
//
//  Deliberately does not yet load or render a real native ad: the promoted-
//  content feed spine (where AdMob ads and Sponsored posts both render) is a
//  separate, larger design pass — see the First Class design spec's original
//  decomposition. This gate exists now so that spine has something correct to
//  call into from day one, instead of retrofitting the entitlement check later.
//

import Foundation
import Observation

@Observable
@MainActor
final class AdsGateway {
    private let entitlement: EntitlementStore

    init(entitlement: EntitlementStore) {
        self.entitlement = entitlement
    }

    /// False whenever the signed-in user is a First Class member. Every
    /// future ad-load call site must check this FIRST and skip the load
    /// entirely — not merely hide the result — when it's false, so a First
    /// Class member never triggers an ad request (and its network/tracking
    /// side effects) in the first place.
    var isEligibleForAds: Bool {
        !entitlement.isFirstClass
    }

    // TODO(admob-spine): the real native-ad load goes here once the feed
    // spine exists, e.g.:
    //
    //   func loadNativeAd(adUnitID: String) async -> GoogleMobileAds.NativeAd? {
    //       guard isEligibleForAds else { return nil }
    //       // Also gate on UMP consent status before this point once the
    //       // consent flow is wired (GoogleUserMessagingPlatform is already
    //       // pulled in as a transitive dependency of GoogleMobileAds).
    //       ...
    //   }
}
