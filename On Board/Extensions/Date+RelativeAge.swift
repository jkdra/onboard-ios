//
//  Date+RelativeAge.swift
//  On Board
//
//  Relative-age labels for posts and comments, in two registers: a compact
//  one for dense surfaces (feed cards, comment rows) and a spelled-out one
//  for the opened post, where there's room to read a real phrase.
//

import Foundation

extension Date {
    /// Short relative age: "now", "5m", "3h", "2d", "1w". For dense
    /// surfaces — the masonry card's corner and comment bylines, where a
    /// full phrase would crowd the content it's annotating.
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

    /// Spelled-out age for the opened post: "just now", "1 min ago",
    /// "45 mins ago", "1 hour ago", "2 days ago".
    ///
    /// Past a week it becomes the calendar date instead ("6-24"): "1w ago"
    /// is a worse answer than the date once a post is old enough to be
    /// history — the week count stops being something a reader can place,
    /// and archived posts are exactly where that happens. Month-day with a
    /// hyphen is the format Jawad specified (2026-08-11), suited to this
    /// app's US campuses; a locale-ordered style would need revisiting
    /// alongside the rest of the app's date handling if that changes.
    var boardVerboseAge: String {
        let seconds = max(0, Date.now.timeIntervalSince(self))
        switch seconds {
        case ..<60:
            return "just now"
        case ..<3_600:
            return Self.phrase(Int(seconds / 60), "min")
        case ..<86_400:
            return Self.phrase(Int(seconds / 3_600), "hour")
        case ..<604_800:
            return Self.phrase(Int(seconds / 86_400), "day")
        default:
            let parts = Calendar.current.dateComponents([.month, .day], from: self)
            guard let month = parts.month, let day = parts.day else { return boardRelativeAge }
            return "\(month)-\(day)"
        }
    }

    /// "1 min ago" / "2 mins ago" — the unit pluralizes, the phrase doesn't
    /// change shape.
    private static func phrase(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s") ago"
    }
}
