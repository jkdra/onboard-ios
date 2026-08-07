//
//  FeatureFlag.swift
//  On Board
//
//  Server-controlled switches for shipped native surfaces.
//
//  Every new feature should be born here, defaulted `false`, and merged and
//  shipped inert. That is what decouples "the feature is finished" from "Apple
//  approved the build" — the code reaches devices on the normal release cadence
//  and is switched on whenever we choose.
//
//  Existing surfaces added retroactively default `true`, because a flag's
//  compiled default must always equal what the app already does.
//

import SwiftUI

enum FeatureFlag: String, CaseIterable, Sendable {
    /// The feed-card → post-detail zoom navigation transition. CLAUDE.md
    /// documents four separate landmine categories around it, and the fallback
    /// (a plain push) is trivially correct — the highest-value switch here.
    case zoomTransition

    /// iOS 26 `glassEffect` styling. The non-glass path already ships to iOS 18
    /// users, so the fallback is proven code rather than a dormant branch.
    case glassEffects

    /// Photo attachments on posts. Lets an upload or moderation incident
    /// degrade to text-only posting instead of taking the whole app down.
    case postPhotoAttachments

    /// The Host's Animalese speech synthesis. Audio work on a hot path is a
    /// plausible performance surface; muting is cheap.
    case hostVoice

    /// Reaction bar overflow: only the first two reactions are always pills,
    /// the rest surface once they have counts, and a "+" holds whatever is
    /// still hidden. New surface, so it ships inert — `false` is the four-pill
    /// bar every user has today.
    case reactionOverflow

    /// Behavior when the server says nothing — must equal what the app does today.
    var compiledDefault: Bool {
        switch self {
        case .zoomTransition, .glassEffects, .postPhotoAttachments, .hostVoice:
            true
        case .reactionOverflow:
            false
        }
    }

    var configKey: String { "flag_\(rawValue)" }
}

extension RemoteConfig {
    /// Resolves a flag for one identity.
    ///
    /// Values are `on`, `off`, or an integer 0–100 for a staged rollout.
    /// Anything else falls back to the compiled default.
    func isEnabled(_ flag: FeatureFlag, for identity: UUID) -> Bool {
        switch rawValue(for: flag.configKey) {
        case "on":
            return true
        case "off":
            return false
        case .some(let raw):
            guard let percentage = Int(raw), (0...100).contains(percentage) else {
                return flag.compiledDefault
            }
            return Self.bucket(identity, salt: flag.rawValue) < percentage
        case nil:
            return flag.compiledDefault
        }
    }

    /// Stable 0–99 bucket for an identity within one flag.
    ///
    /// Salted with the flag name on purpose: bucketing on identity alone would
    /// put the same unlucky ~10% of users into *every* staged rollout forever,
    /// turning a sampling strategy into one permanently experimented-on cohort.
    ///
    /// Uses `StableHash`, never `hashValue` — Swift seeds that per process, so a
    /// user would move in and out of the rollout on every cold launch.
    static func bucket(_ identity: UUID, salt: String) -> Int {
        Int(StableHash.fnv1a("\(identity.uuidString):\(salt)") % 100)
    }
}

// MARK: - Glass effects

private struct GlassEffectsEnabledKey: EnvironmentKey {
    /// Defaults to `true` so every `#Preview` and any view rendered outside the
    /// app's environment keeps its current appearance. Deliberately an
    /// EnvironmentValue rather than reading `RemoteConfigStore` in each leaf
    /// view: `@Environment(RemoteConfigStore.self)` traps at runtime when the
    /// store isn't in the environment, which would break every preview of
    /// ReactionBar, GridCard, CountdownCard and OnboardingProgressBar.
    static let defaultValue = true
}

private struct PhotoAttachmentsEnabledKey: EnvironmentKey {
    /// Defaults to `true` for the same preview-safety reason as
    /// `GlassEffectsEnabledKey`.
    static let defaultValue = true
}

private struct CommentMaxLengthKey: EnvironmentKey {
    static let defaultValue = 280
}

private struct ProfileFieldLimitsKey: EnvironmentKey {
    /// (displayName, bio). Paired because both captions and `canSave` read them
    /// together, and splitting them into two keys would let one drift.
    static let defaultValue = (displayName: 50, bio: 300)
}

private struct HandleChangeRuleKey: EnvironmentKey {
    /// (windowDays, maxPerWindow) — mirrors the server's username-change rule.
    static let defaultValue = (windowDays: 14, maxPerWindow: 2)
}

private struct EnabledReactionsKey: EnvironmentKey {
    /// The compiled set, so previews and any view outside the app's environment
    /// render the full bar.
    static let defaultValue = Reaction.defaultOrder
}

private struct ReactionOverflowEnabledKey: EnvironmentKey {
    /// `false`, unlike its neighbours here: those gate surfaces that already
    /// shipped, so their default has to be "what the app does today". This one
    /// gates a change that has never shipped, and the same rule points the
    /// other way — previews and out-of-environment views must keep showing the
    /// flat four-pill bar.
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Gates the iOS 26 `glassEffect` styling. Set once at the app root from
    /// `FeatureFlag.glassEffects`; read by each `#available(iOS 26.0, *)` site.
    ///
    /// The fallback path isn't dormant code — it is what every iOS 18 user runs
    /// today, so switching this off lands on a well-exercised branch.
    var glassEffectsEnabled: Bool {
        get { self[GlassEffectsEnabledKey.self] }
        set { self[GlassEffectsEnabledKey.self] = newValue }
    }

    /// Gates photo attachments on posts. Switching this off degrades the app to
    /// text-only posting instead of taking it down, which is the useful move if
    /// the upload path or image moderation has an incident.
    ///
    /// Existing posts keep their images; only the attach/replace control is
    /// withdrawn.
    var photoAttachmentsEnabled: Bool {
        get { self[PhotoAttachmentsEnabledKey.self] }
        set { self[PhotoAttachmentsEnabledKey.self] = newValue }
    }

    /// Which reactions the UI offers, in order. Set once at the app root from
    /// `RemoteConfig.enabledReactions`; read by `ReactionBar`, `GridCard`'s
    /// top-3 row, and `PopScoreView`.
    ///
    /// This is the lever for withdrawing a reaction — `dislike` on a campus
    /// board being the obvious candidate if it turns into a pile-on mechanism —
    /// without waiting on App Review. Display-only: existing rows keep counting
    /// server-side and return intact when the key is removed.
    var enabledReactions: [Reaction] {
        get { self[EnabledReactionsKey.self] }
        set { self[EnabledReactionsKey.self] = newValue }
    }

    /// Collapses the reaction bar to its first two reactions plus a "+", with
    /// the rest surfacing as real pills once they have counts.
    ///
    /// Composes with `enabledReactions` rather than duplicating it: the split
    /// is positional (first two stay, the tail overflows), so withdrawing a
    /// reaction server-side still works and reordering the array is what
    /// decides which two are permanent.
    var reactionOverflowEnabled: Bool {
        get { self[ReactionOverflowEnabledKey.self] }
        set { self[ReactionOverflowEnabledKey.self] = newValue }
    }

    /// Max comment length. A display + validation hint only — `comments.body`
    /// is server-authoritative, so raise the column before raising this.
    var commentMaxLength: Int {
        get { self[CommentMaxLengthKey.self] }
        set { self[CommentMaxLengthKey.self] = newValue }
    }

    /// Profile display-name and bio limits. Same server-authoritative caveat.
    var profileFieldLimits: (displayName: Int, bio: Int) {
        get { self[ProfileFieldLimitsKey.self] }
        set { self[ProfileFieldLimitsKey.self] = newValue }
    }

    /// Username-change rate limit shown in the profile editor. Mirrors the
    /// server rule; passing it through config means a server-side retune
    /// reaches the UI without a release.
    var handleChangeRule: (windowDays: Int, maxPerWindow: Int) {
        get { self[HandleChangeRuleKey.self] }
        set { self[HandleChangeRuleKey.self] = newValue }
    }
}
