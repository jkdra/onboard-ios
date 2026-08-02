//
//  RemoteConfigTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct RemoteConfigDefaultsTests {
    /// The load-bearing guarantee: a server saying nothing must behave exactly
    /// like a build with no remote config. Every value here is the constant that
    /// was compiled in before this subsystem existed.
    @Test func emptyConfigReturnsCompiledDefaults() {
        let config = RemoteConfig.empty
        #expect(config.feedPollSeconds == 45)
        #expect(config.otpCooldownSeconds == 30)
        #expect(config.referralOneMonthThreshold == 4)
        #expect(config.referralThreeMonthThreshold == 5)
        #expect(config.referralDisclosureThreshold == 3)
        #expect(config.boardClearingSoonHours == 3)
        #expect(config.boardFinalHourLockoutHours == 1)
        #expect(config.handleChangeWindowDays == 14)
        #expect(config.handleChangeMaxPerWindow == 2)
        #expect(config.commentMaxLength == 280)
        #expect(config.bioMaxLength == 300)
        #expect(config.displayNameMaxLength == 50)
        #expect(config.maxCachedArchiveWeeks == 3)
        #expect(config.referralShareMessage == nil)
        #expect(config.minSupportedVersion == nil)
    }

    @Test func serverValuesOverrideDefaults() {
        let config = RemoteConfig(values: ["feed_poll_seconds": "120", "comment_max_length": "500"])
        #expect(config.feedPollSeconds == 120)
        #expect(config.commentMaxLength == 500)
        #expect(config.otpCooldownSeconds == 30)
    }

    @Test func unparseableValuesFallBackInsteadOfCrashing() {
        let config = RemoteConfig(values: ["feed_poll_seconds": "soon", "comment_max_length": ""])
        #expect(config.feedPollSeconds == 45)
        #expect(config.commentMaxLength == 280)
    }

    @Test func unknownKeysAreIgnored() {
        let config = RemoteConfig(values: ["some_future_key": "1", "feed_poll_seconds": "90"])
        #expect(config.feedPollSeconds == 90)
    }

    @Test func decodesFromTheRPCShape() throws {
        let json = Data(#"{"feed_poll_seconds":"90","flag_zoomTransition":"off"}"#.utf8)
        let values = try JSONDecoder().decode([String: String].self, from: json)
        let config = RemoteConfig(values: values)
        #expect(config.feedPollSeconds == 90)
        #expect(config.rawValue(for: "flag_zoomTransition") == "off")
    }
}

@MainActor
struct FeatureFlagTests {
    private let identity = UUID(uuidString: "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01")!

    @Test func absentFlagUsesCompiledDefault() {
        let config = RemoteConfig.empty
        for flag in FeatureFlag.allCases {
            #expect(config.isEnabled(flag, for: identity) == flag.compiledDefault)
        }
    }

    /// Every flag here wraps a surface that already ships enabled, so shipping
    /// this build must not silently turn any of them off.
    @Test func everyExistingSurfaceDefaultsOn() {
        for flag in FeatureFlag.allCases {
            #expect(flag.compiledDefault)
        }
    }

    @Test func explicitOnAndOffWin() {
        let on = RemoteConfig(values: ["flag_zoomTransition": "on"])
        let off = RemoteConfig(values: ["flag_zoomTransition": "off"])
        #expect(on.isEnabled(.zoomTransition, for: identity))
        #expect(!off.isEnabled(.zoomTransition, for: identity))
    }

    @Test func zeroPercentIsOffForEveryoneAndHundredIsOnForEveryone() {
        let none = RemoteConfig(values: ["flag_zoomTransition": "0"])
        let all = RemoteConfig(values: ["flag_zoomTransition": "100"])
        for _ in 0..<200 {
            let id = UUID()
            #expect(!none.isEnabled(.zoomTransition, for: id))
            #expect(all.isEnabled(.zoomTransition, for: id))
        }
    }

    @Test func bucketingIsStableForTheSameIdentity() {
        let config = RemoteConfig(values: ["flag_zoomTransition": "50"])
        let first = config.isEnabled(.zoomTransition, for: identity)
        for _ in 0..<50 {
            #expect(config.isEnabled(.zoomTransition, for: identity) == first)
        }
    }

    @Test func aPartialRolloutSelectsRoughlyThatShare() {
        let config = RemoteConfig(values: ["flag_zoomTransition": "50"])
        let ids = (0..<1000).map { _ in UUID() }
        let enabled = ids.filter { config.isEnabled(.zoomTransition, for: $0) }.count
        // Wide band — this pins "it actually samples", not statistical precision.
        #expect(enabled > 350 && enabled < 650)
    }

    /// The salt is what stops the same unlucky cohort from receiving every
    /// staged rollout forever. Without it, two flags at 50% select identical users.
    @Test func differentFlagsAtTheSamePercentageSelectDifferentCohorts() {
        let config = RemoteConfig(values: [
            "flag_zoomTransition": "50",
            "flag_glassEffects": "50"
        ])
        let ids = (0..<500).map { _ in UUID() }
        let a = Set(ids.filter { config.isEnabled(.zoomTransition, for: $0) })
        let b = Set(ids.filter { config.isEnabled(.glassEffects, for: $0) })
        #expect(a != b)
    }

    @Test func unparseableValueFallsBackToCompiledDefault() {
        let config = RemoteConfig(values: ["flag_zoomTransition": "maybe"])
        #expect(config.isEnabled(.zoomTransition, for: identity) == FeatureFlag.zoomTransition.compiledDefault)
    }

    @Test func outOfRangePercentageFallsBackToCompiledDefault() {
        let config = RemoteConfig(values: ["flag_zoomTransition": "150"])
        #expect(config.isEnabled(.zoomTransition, for: identity) == FeatureFlag.zoomTransition.compiledDefault)
    }
}

@MainActor
struct AppVersionComparisonTests {
    /// The bug this pins: "1.10" < "1.9" as a string comparison, which would
    /// gate users out of a newer build.
    @Test func comparesNumericallyNotLexically() {
        #expect(AppVersion.isOlder("1.9", than: "1.10"))
        #expect(!AppVersion.isOlder("1.10", than: "1.9"))
    }

    @Test func equalVersionsAreNotOlder() {
        #expect(!AppVersion.isOlder("1.1.1", than: "1.1.1"))
    }

    @Test func handlesDifferingComponentCounts() {
        #expect(AppVersion.isOlder("1.1", than: "1.1.1"))
        #expect(!AppVersion.isOlder("1.1.1", than: "1.1"))
    }

    @Test func malformedVersionsAreNeverTreatedAsOlder() {
        #expect(!AppVersion.isOlder("banana", than: "1.1.1"))
        #expect(!AppVersion.isOlder("1.1.1", than: ""))
    }
}

@MainActor
struct UpdateRequirementTests {
    @Test func absentKeysRequireNothing() {
        #expect(RemoteConfig.empty.updateRequirement(forCurrentVersion: "1.1") == .none)
    }

    @Test func belowRecommendedIsSoft() {
        let config = RemoteConfig(values: ["recommended_version": "1.2"])
        #expect(config.updateRequirement(forCurrentVersion: "1.1") == .recommended)
    }

    @Test func belowMinimumIsBlockingAndBeatsRecommended() {
        let config = RemoteConfig(values: [
            "min_supported_version": "1.2",
            "recommended_version": "1.3"
        ])
        #expect(config.updateRequirement(forCurrentVersion: "1.1") == .required)
    }

    @Test func atOrAboveBothRequiresNothing() {
        let config = RemoteConfig(values: [
            "min_supported_version": "1.1",
            "recommended_version": "1.1"
        ])
        #expect(config.updateRequirement(forCurrentVersion: "1.1") == .none)
    }
}

@MainActor
struct RemoteConfigStoreTests {
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsEmptyWithNoStoredConfig() {
        let store = RemoteConfigStore(defaults: isolatedDefaults("test.rc.empty"))
        #expect(store.config == .empty)
        #expect(store.config.feedPollSeconds == 45)
    }

    @Test func restoresStoredConfigOnInit() {
        let defaults = isolatedDefaults("test.rc.restore")
        RemoteConfigStore(defaults: defaults).apply(["feed_poll_seconds": "120"])
        #expect(RemoteConfigStore(defaults: defaults).config.feedPollSeconds == 120)
    }

    @Test func installIdentityIsStableAcrossInstances() {
        let defaults = isolatedDefaults("test.rc.identity")
        let first = RemoteConfigStore(defaults: defaults).installIdentity
        #expect(RemoteConfigStore(defaults: defaults).installIdentity == first)
    }

    @Test func flagsResolveWithAndWithoutASignedInUser() {
        let store = RemoteConfigStore(defaults: isolatedDefaults("test.rc.flags"))
        store.apply(["flag_zoomTransition": "100"])
        #expect(store.isEnabled(.zoomTransition, for: UUID()))
        #expect(store.isEnabled(.zoomTransition, for: nil))
    }

    /// The test bundle has no Secrets.xcconfig, so the factory hands back no
    /// client — refresh must record that as `.unavailable` (an expected state
    /// the inspector displays), never as an error.
    @Test func refreshWithoutAClientReportsUnavailable() async {
        // An explicitly unconfigured AppConfiguration, NOT .current: with
        // Secrets.xcconfig present the test host is live-configured, and this
        // test must not depend on which build flavor it runs in (or make a
        // real network call from the suite).
        let unconfigured = AppConfiguration(supabaseURL: nil, supabaseAnonKey: nil, googleClientID: nil)
        let store = RemoteConfigStore(defaults: isolatedDefaults("test.rc.status"), configuration: unconfigured)
        #expect(store.fetchStatus == .notYetFetched)
        await store.refresh()
        #expect(store.fetchStatus == .unavailable)
        #expect(store.config == .empty)
    }

    @Test func applyingIdenticalValuesLeavesStorageUnchanged() {
        let defaults = isolatedDefaults("test.rc.nowrite")
        let store = RemoteConfigStore(defaults: defaults)
        store.apply(["feed_poll_seconds": "120"])
        let first = defaults.object(forKey: RemoteConfigStore.storageKey) as? [String: String]
        store.apply(["feed_poll_seconds": "120"])
        let second = defaults.object(forKey: RemoteConfigStore.storageKey) as? [String: String]
        #expect(first == second)
    }
}
