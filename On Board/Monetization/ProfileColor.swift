//
//  ProfileColor.swift
//  On Board
//
//  On Board First Class's first REAL (not just listed) perk: tint your own
//  avatar's ring with an accent color. Deliberately client-side, per-device
//  only — no `Profile`/Supabase field, no backend change — matching the
//  First Class design spec's "cheapest, safest perk to prove the gate"
//  scoping. Only the owning device sees the tint for now; showing it to
//  OTHER users' devices needs a synced `profiles` column, a clearly
//  separate, deferred step (not silently pretended to work today).
//

import SwiftUI

enum ProfileColor: String, CaseIterable, Identifiable, Sendable {
    case none
    case coral
    case amber
    case sage
    case teal
    case periwinkle
    case plum

    var id: String { rawValue }

    /// `nil` renders as the default neutral ring — same as a non-member.
    var color: Color? {
        switch self {
        case .none: nil
        case .coral: Color(red: 0.90, green: 0.40, blue: 0.36)
        case .amber: Color(red: 0.91, green: 0.67, blue: 0.22)
        case .sage: Color(red: 0.53, green: 0.66, blue: 0.47)
        case .teal: Color(red: 0.22, green: 0.60, blue: 0.60)
        case .periwinkle: Color(red: 0.47, green: 0.54, blue: 0.87)
        case .plum: Color(red: 0.61, green: 0.41, blue: 0.67)
        }
    }

    var label: String {
        switch self {
        case .none: "None"
        case .coral: "Coral"
        case .amber: "Amber"
        case .sage: "Sage"
        case .teal: "Teal"
        case .periwinkle: "Periwinkle"
        case .plum: "Plum"
        }
    }
}
