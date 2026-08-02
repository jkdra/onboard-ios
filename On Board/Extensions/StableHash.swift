//
//  StableHash.swift
//  On Board
//
//  A process-stable hash.
//
//  `String.hashValue` is seeded per process, so the same input produces a
//  different value after every app restart. That makes it unusable for anything
//  the user can perceive across launches — a color derived from it would flicker
//  on every cold start, and a feature-flag bucket derived from it would move a
//  user in and out of a staged rollout every time they reopened the app.
//  Use this instead for any of those.
//

import Foundation

enum StableHash {
    /// FNV-1a, 64-bit. Chosen for being tiny, dependency-free, and stable
    /// forever — not for cryptographic strength. Never use for security.
    nonisolated static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
