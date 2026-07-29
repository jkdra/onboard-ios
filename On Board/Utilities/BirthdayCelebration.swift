//
//  BirthdayCelebration.swift
//  On Board
//
//  Shared logic for the birthday moment: is today the user's birthday, and
//  (for the feed) has the once-a-year greeting already played. The feed
//  celebration fires once per year per user; the profile celebration is a
//  visible-to-anyone signal that plays each visit (finite each time), so it
//  isn't gated.
//

import Foundation

enum BirthdayCelebration {

    /// True when today (local) matches the month + day of the stored
    /// "yyyy-MM-dd" birthday string.
    static func isToday(_ birthday: String?) -> Bool {
        guard let date = parse(birthday) else { return false }
        let cal = Calendar.current
        let b = cal.dateComponents([.month, .day], from: date)
        let t = cal.dateComponents([.month, .day], from: Date())
        return b.month == t.month && b.day == t.day
    }

    /// "August 12" — the month/day used in the profile greeting cross-fade.
    static func monthDayString(_ birthday: String?) -> String? {
        guard let date = parse(birthday) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }

    // MARK: Feed gating — once per birthday, per user

    private static func feedKey(for userID: UUID) -> String {
        let year = Calendar.current.component(.year, from: Date())
        return "birthdayFeedShown.\(userID.uuidString).\(year)"
    }

    static func feedShown(for userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: feedKey(for: userID))
    }

    static func markFeedShown(for userID: UUID) {
        UserDefaults.standard.set(true, forKey: feedKey(for: userID))
    }

    // MARK: -

    private static func parse(_ raw: String?) -> Date? {
        WireDateParser.date(from: raw)
    }
}
