//
//  BoardSchedule.swift
//  On Board
//
//  Shared Monday-midnight reset schedule used by the feed background
//  and the countdown card.
//

import Foundation

/// Where the active week sits relative to its own deadline.
///
/// This exists because the predicates below used to be written as bare
/// `remaining < window` checks guarded by `remaining > 0`. That guard is correct
/// for "are we in the final hour" and catastrophically wrong as a gate: the moment
/// the clock reached zero *every* predicate reported false, so the board fell back
/// to its wide-open styling — frozen countdown, red caption stuck at 00:00:00, and
/// a re-enabled compose button offering to post into a week that had already ended.
/// Expiry is a real state and it lasts until the rollover lands, which on a slow or
/// failed refresh can be a long time. Route decisions through `phase`, not through
/// hand-rolled window math.
enum BoardPhase: Equatable {
    /// More than three hours left.
    case open
    /// Final three hours. Urgent styling, posting still allowed.
    case clearingSoon
    /// Final hour. Posting is closed so nobody is mid-compose at the wipe.
    case finalHour
    /// The deadline has passed and the new week hasn't arrived yet.
    case expired

    /// Posting closes for the final hour and stays closed through expiry.
    var allowsPosting: Bool {
        self == .open || self == .clearingSoon
    }

    /// Drives the red pulse, the red countdown, and the nav-bar countdown.
    /// Deliberately true for `.expired` — an ended board is not a calm board.
    var isUrgent: Bool {
        self != .open
    }

    var hasEnded: Bool {
        self == .expired
    }
}

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

    /// Seconds left in the week, or nil when there's no way to tell (no `weekEnd`
    /// and the calendar couldn't resolve next Monday). Note `secondsUntilWeekEnd`
    /// clamps at zero, so "0 remaining" *is* the expired signal.
    private static func remainingSeconds(
        weekEnd: Date?,
        from now: Date,
        calendar: Calendar
    ) -> TimeInterval? {
        if let weekEnd {
            return secondsUntilWeekEnd(weekEnd, from: now)
        }
        return secondsUntilNextMonday(from: now, calendar: calendar)
    }

    /// The single source of truth for where the week stands. Every gate — posting,
    /// urgency styling, interaction — should derive from this rather than
    /// re-deriving window math and re-introducing the expiry hole.
    static func phase(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> BoardPhase {
        // Undeterminable schedule: treat as a normal open week rather than
        // locking the board down over a calendar failure.
        guard let remaining = remainingSeconds(weekEnd: weekEnd, from: now, calendar: calendar) else {
            return .open
        }
        if remaining <= 0 { return .expired }
        if remaining < 3_600 { return .finalHour }
        if remaining < 10_800 { return .clearingSoon }
        return .open
    }

    /// True during the final hour before the weekly board reset. Kept narrow on
    /// purpose — this is "the last hour", not "posting is closed". For the gate,
    /// use `phase(...).allowsPosting`, which also covers expiry.
    static func isWithinFinalHour(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        phase(weekEnd: weekEnd, from: now, calendar: calendar) == .finalHour
    }

    /// True once the week's deadline has passed and the rollover hasn't landed.
    static func isExpired(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        phase(weekEnd: weekEnd, from: now, calendar: calendar) == .expired
    }

    /// Banner text for the closed-posting window. Nil while posting is still open.
    static func finalHourBannerText(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        let phase = phase(weekEnd: weekEnd, from: now, calendar: calendar)
        guard !phase.allowsPosting else { return nil }
        guard phase != .expired else { return "This board has closed" }
        let t = timeRemaining(weekEnd: weekEnd, from: now, calendar: calendar)
        if t.hours > 0 {
            return "Board clears in \(t.hours)h \(t.minutes)m"
        } else if t.minutes > 1 {
            return "Board clears in \(t.minutes) minutes"
        } else {
            return "Board clears very soon"
        }
    }

    /// True during the final 3 hours before the weekly board reset — and through
    /// expiry, so the urgency treatment doesn't snap back to calm at 00:00:00 while
    /// the board is sitting there dead waiting on a rollover.
    static func isClearingSoon(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        phase(weekEnd: weekEnd, from: now, calendar: calendar).isUrgent
    }

    static func timeRemaining(
        weekEnd: Date? = nil,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> (days: Int, hours: Int, minutes: Int, seconds: Int, totalSeconds: TimeInterval) {
        let totalSeconds: TimeInterval?
        if let weekEnd {
            totalSeconds = secondsUntilWeekEnd(weekEnd, from: now)
        } else {
            totalSeconds = secondsUntilNextMonday(from: now, calendar: calendar)
        }
        guard let totalSeconds else {
            return (0, 0, 0, 0, 0)
        }
        let seconds = max(0, Int(totalSeconds))
        return (
            days: seconds / 86_400,
            hours: (seconds % 86_400) / 3_600,
            minutes: (seconds % 3_600) / 60,
            seconds: seconds % 60,
            totalSeconds: totalSeconds
        )
    }
}
