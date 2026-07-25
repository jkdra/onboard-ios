//
//  GraduationMonth.swift
//  On Board
//
//  Single source for formatting `OnboardingStatus.expectedGraduation`, whose
//  wire value is a first-of-month date string ("yyyy-MM-01"). Producing that
//  wire string and parsing/displaying the stored value used to be duplicated
//  across the live service, the mock service, and the settings UI — they now
//  share this.
//

import Foundation

enum GraduationMonth {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// The wire string the backend expects — the given date's month, normalized
    /// to day 01. We only ever collect month + year.
    static func wireString(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = posix
        f.dateFormat = "yyyy-MM-01"
        return f.string(from: date)
    }

    /// Month + year from a stored "yyyy-MM-dd" value, or nil if unset/unparseable.
    static func parse(_ raw: String?) -> (month: Int, year: Int)? {
        guard let date = date(from: raw) else { return nil }
        let c = Calendar.current.dateComponents([.month, .year], from: date)
        guard let m = c.month, let y = c.year else { return nil }
        return (m, y)
    }

    /// Localized "May 2027" for display, or nil if unset/unparseable.
    static func display(_ raw: String?) -> String? {
        guard let date = date(from: raw) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMMM yyyy"
        return out.string(from: date)
    }

    private static func date(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }
}
