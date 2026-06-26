//
//  BoardSchedule.swift
//  On Board
//
//  Shared Monday-midnight reset schedule used by the feed background
//  and the countdown card.
//

import Foundation

enum BoardSchedule {
    private static func mondayCalendar(_ calendar: Calendar) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar
    }

    /// Start of the Monday–Monday board week containing `date`.
    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let calendar = mondayCalendar(calendar)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// The seven calendar days for a board week (Monday first).
    static func daysInWeek(starting weekStart: Date, calendar: Calendar = .current) -> [Date] {
        let calendar = mondayCalendar(calendar)
        let start = calendar.startOfDay(for: weekStart)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Every Monday between two dates, inclusive.
    static func weekStarts(
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let calendar = mondayCalendar(calendar)
        var weeks: [Date] = []
        var cursor = startOfWeek(containing: start, calendar: calendar)
        let final = startOfWeek(containing: end, calendar: calendar)

        while cursor <= final {
            weeks.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// Seconds until a known week boundary (server `ends_at` when available).
    static func secondsUntilWeekEnd(_ end: Date, from now: Date = .now) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    /// Seconds from `now` until the next Monday at 00:00 (local time).
    static func secondsUntilNextMonday(from now: Date = .now, calendar: Calendar = .current) -> TimeInterval? {
        var components = DateComponents()
        components.weekday = 2 // Monday
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard let nextMonday = calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime
        ) else { return nil }

        return nextMonday.timeIntervalSince(now)
    }

    /// True during the final hour before the weekly board reset.
    static func isWithinFinalHour(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let remaining: TimeInterval?
        if let weekEnd {
            remaining = secondsUntilWeekEnd(weekEnd, from: now)
        } else {
            remaining = secondsUntilNextMonday(from: now, calendar: calendar)
        }
        guard let remaining else { return false }
        return remaining > 0 && remaining < 3_600
    }

    /// Banner text shown in the final hour. Returns nil when more than an hour remains.
    static func finalHourBannerText(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard isWithinFinalHour(weekEnd: weekEnd, from: now, calendar: calendar) else { return nil }
        let t = timeRemaining(weekEnd: weekEnd, from: now, calendar: calendar)
        if t.hours > 0 {
            return "Board clears in \(t.hours)h \(t.minutes)m"
        } else if t.minutes > 1 {
            return "Board clears in \(t.minutes) minutes"
        } else {
            return "Board clears very soon"
        }
    }

    /// True during the final 12 hours before the weekly board reset.
    static func isClearingSoon(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let remaining: TimeInterval?
        if let weekEnd {
            remaining = secondsUntilWeekEnd(weekEnd, from: now)
        } else {
            remaining = secondsUntilNextMonday(from: now, calendar: calendar)
        }
        guard let remaining else { return false }
        let twelveHours: TimeInterval = 12 * 60 * 60
        return remaining > 0 && remaining < twelveHours
    }

    static func timeRemaining(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> (days: Int, hours: Int, minutes: Int) {
        let totalSeconds: TimeInterval?
        if let weekEnd {
            totalSeconds = secondsUntilWeekEnd(weekEnd, from: now)
        } else {
            totalSeconds = secondsUntilNextMonday(from: now, calendar: calendar)
        }
        guard let totalSeconds else {
            return (0, 0, 0)
        }
        let seconds = max(0, Int(totalSeconds))
        return (
            days: seconds / 86_400,
            hours: (seconds % 86_400) / 3_600,
            minutes: (seconds % 3_600) / 60
        )
    }
}
