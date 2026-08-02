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

@MainActor
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

@MainActor
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

@MainActor
struct BoardWeekStatusDecodingTests {
    private func weekJSON(status: String) -> String {
        """
        {
            "id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01",
            "board_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E02",
            "starts_at": "2026-08-03T00:00:00Z",
            "ends_at": "2026-08-10T00:00:00Z",
            "status": "\(status)",
            "post_count": 4
        }
        """
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func decodesKnownStatus() throws {
        let week = try decoder.decode(BoardWeek.self, from: Data(weekJSON(status: "archived").utf8))
        #expect(week.status == .archived)
    }

    @Test func unknownStatusDegradesToReadOnlyInsteadOfThrowing() throws {
        let week = try decoder.decode(BoardWeek.self, from: Data(weekJSON(status: "frozen").utf8))
        #expect(week.status == .archived)
        #expect(week.isReadOnly)
    }

    @Test func arrayDecodeSurvivesOneUnknownStatus() throws {
        let json = "[\(weekJSON(status: "active")),\(weekJSON(status: "frozen"))]"
        let weeks = try decoder.decode([BoardWeek].self, from: Data(json.utf8))
        #expect(weeks.count == 2)
        #expect(weeks[0].status == .active)
        #expect(weeks[1].status == .archived)
    }
}

@MainActor
struct ReactionRowDecodingTests {
    @Test func arrayDecodeSurvivesAnUnknownReactionType() throws {
        let json = Data("""
        [
            {"post_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01", "type": "like"},
            {"post_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E02", "type": "sparkle"}
        ]
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([SupabaseBoardService.UserReactionRow].self, from: json)
        #expect(rows.count == 2)

        // The unknown type is dropped at mapping time, not decode time —
        // mapping it onto a known reaction would inflate that reaction's count.
        let mapped = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            Reaction(rawValue: row.type).map { (row.postId, $0) }
        })
        #expect(mapped.count == 1)
        #expect(mapped.values.first == .like)
    }
}

@MainActor
struct OnboardingStepDecodingTests {
    @Test func decodesKnownStep() throws {
        let step = try JSONDecoder().decode(OnboardingStep.self, from: Data(#""school_verify""#.utf8))
        #expect(step == .schoolVerify)
    }

    @Test func unknownStepDecodesAsUnrecognizedInsteadOfThrowing() throws {
        let step = try JSONDecoder().decode(OnboardingStep.self, from: Data(#""alumni_verify""#.utf8))
        #expect(step == .unrecognized)
    }

    /// `.unrecognized` must never appear in `allCases`:
    /// `OnboardingCoordinator.rank(_:)` uses `allCases.firstIndex(of:)` for step
    /// ordering and `OnboardingProgressBar` takes a step index, so a sentinel in
    /// that list would silently shift both.
    @Test func unrecognizedIsExcludedFromAllCases() {
        #expect(!OnboardingStep.allCases.contains(.unrecognized))
        #expect(OnboardingStep.allCases.count == 8)
    }

    @Test func knownStepsStillRoundTrip() throws {
        for step in OnboardingStep.allCases {
            let data = try JSONEncoder().encode(step)
            #expect(try JSONDecoder().decode(OnboardingStep.self, from: data) == step)
        }
    }

    /// An unrecognized step must route to the update screen alone — not stacked
    /// on top of the real steps, which would offer a back button into a flow
    /// this build cannot complete.
    @Test func unrecognizedRoutesToItsOwnPath() {
        #expect(OnboardingCoordinator.targetPath(for: .unrecognized, isSignedIn: true) == [.unrecognized])
    }

    @Test func signedOutStillGetsAnEmptyPath() {
        #expect(OnboardingCoordinator.targetPath(for: .unrecognized, isSignedIn: false).isEmpty)
    }
}

@MainActor
struct CommentVoteRowDecodingTests {
    @Test func arrayDecodeSurvivesAnUnknownVote() throws {
        let json = Data("""
        [
            {"comment_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01", "vote": "like"},
            {"comment_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E02", "vote": "superlike"}
        ]
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([SupabaseBoardService.UserCommentVoteRow].self, from: json)
        #expect(rows.count == 2)

        let mapped = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            CommentVote(rawValue: row.vote).map { (row.commentId, $0) }
        })
        #expect(mapped.count == 1)
        #expect(mapped.values.first == .like)
    }
}
