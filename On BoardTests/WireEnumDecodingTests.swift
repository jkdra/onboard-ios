//
//  WireEnumDecodingTests.swift
//  On BoardTests
//
//  Pins forward compatibility for every enum that crosses the Supabase wire.
//  Each of these is decoded inside an array, so a throw on one unknown value
//  fails the whole response — see the `arrayDecodeSurvives...` cases, which are
//  the ones that actually pin the bug.
//

import Foundation
import Testing
@testable import On_Board

struct StableHashTests {
    @Test func isDeterministicForTheSameInput() {
        #expect(StableHash.fnv1a("onboard") == StableHash.fnv1a("onboard"))
    }

    @Test func differsForDifferentInputs() {
        #expect(StableHash.fnv1a("onboard") != StableHash.fnv1a("onboarding"))
    }

    @Test func matchesKnownFNV1aVector() {
        // Canonical FNV-1a 64-bit test vector for "a".
        #expect(StableHash.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    }
}

struct PostToneDecodingTests {
    @Test func decodesKnownTone() throws {
        let tone = try JSONDecoder().decode(PostTone.self, from: Data(#""mint""#.utf8))
        #expect(tone == .mint)
    }

    @Test func mapsUnknownToneToAKnownToneInsteadOfThrowing() throws {
        let tone = try JSONDecoder().decode(PostTone.self, from: Data(#""crimson""#.utf8))
        #expect(PostTone.allCases.contains(tone))
    }

    @Test func unknownToneMapsDeterministically() {
        #expect(PostTone.stableFallback(for: "crimson") == PostTone.stableFallback(for: "crimson"))
    }

    @Test func differentUnknownTonesDoNotAllCollapseToOneColor() {
        let raws = ["crimson", "amber", "violet", "cyan", "magenta", "olive", "slate", "rose"]
        let mapped = Set(raws.map { PostTone.stableFallback(for: $0) })
        #expect(mapped.count > 1)
    }

    /// The case that matters: one unknown tone must not take the whole feed with it.
    @Test func arrayDecodeSurvivesOneUnknownTone() throws {
        let json = Data(#"["blue","crimson","mint"]"#.utf8)
        let tones = try JSONDecoder().decode([PostTone].self, from: json)
        #expect(tones.count == 3)
        #expect(tones[0] == .blue)
        #expect(tones[2] == .mint)
    }

    @Test func knownTonesStillRoundTrip() throws {
        for tone in PostTone.allCases {
            let data = try JSONEncoder().encode(tone)
            #expect(try JSONDecoder().decode(PostTone.self, from: data) == tone)
        }
    }
}
