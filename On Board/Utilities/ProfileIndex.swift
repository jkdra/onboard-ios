//
//  ProfileIndex.swift
//  On Board
//
//  Fast O(1) profile lookups by id and handle. Rebuilt when the
//  profile list changes (sample data or live Supabase fetch).
//

import Foundation

struct ProfileIndex: Sendable {
    private let byID: [UUID: Profile]
    private let byHandle: [String: Profile]

    init(profiles: [Profile]) {
        byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        byHandle = Dictionary(
            profiles.map { ($0.handle.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func profile(id: UUID) -> Profile? {
        byID[id]
    }

    func profile(handle: String) -> Profile? {
        byHandle[handle.lowercased()]
    }
}
