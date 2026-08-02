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

import Foundation

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

    /// Behavior when the server says nothing — must equal what the app does today.
    var compiledDefault: Bool {
        switch self {
        case .zoomTransition, .glassEffects, .postPhotoAttachments, .hostVoice:
            true
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
