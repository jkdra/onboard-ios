//
//  Date+RelativeAge.swift
//  On Board
//
//  Compact relative-age labels for posts and comments. Boards run weekly, so this
//  never needs months/years — the longest a post lives is one week.
//

import Foundation

extension Date {
    /// Short relative age: "now", "5m", "3h", "2d", "1w".
    var boardRelativeAge: String {
        let seconds = max(0, Date.now.timeIntervalSince(self))
        switch seconds {
        case ..<60:      return "now"
        case ..<3_600:   return "\(Int(seconds / 60))m"
        case ..<86_400:  return "\(Int(seconds / 3_600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default:         return "\(Int(seconds / 604_800))w"
        }
    }
}
