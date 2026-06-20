//
//  ArchiveCalendarBuilder.swift
//  On Board
//
//  Builds Monday-start week rows for the archive calendar.
//

import Foundation

struct ArchiveCalendarDay: Identifiable, Hashable {
    let id: Date
    let date: Date
    let dayOfMonth: Int
    let month: Int
    let year: Int

    var isToday: Bool
    var isBoardOrigin: Bool
}

struct ArchiveMonthSegment: Identifiable, Hashable {
    var id: String { "\(year)-\(month)-\(dayCount)" }
    let month: Int
    let year: Int
    let dayCount: Int
}

struct CalendarMonth: Hashable {
    let month: Int
    let year: Int

    init(month: Int, year: Int) {
        self.month = month
        self.year = year
    }

    init(segment: ArchiveMonthSegment) {
        month = segment.month
        year = segment.year
    }

    func contains(_ day: ArchiveCalendarDay) -> Bool {
        day.month == month && day.year == year
    }
}

struct ArchiveCalendarWeek: Identifiable, Hashable {
    let id: Date
    let weekStart: Date
    let days: [ArchiveCalendarDay]
    let monthSegments: [ArchiveMonthSegment]
    let boardWeek: BoardWeek?

    /// True when this week contains days from more than one calendar month.
    var spansMonthBoundary: Bool { monthSegments.count > 1 }

    /// Month with the most days in this week — used for scroll focus.
    var dominantMonth: CalendarMonth? {
        guard let segment = monthSegments.max(by: { $0.dayCount < $1.dayCount }) else { return nil }
        return CalendarMonth(segment: segment)
    }
}

enum ArchiveCalendarBuilder {
    static let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func build(
        boardWeeks: [BoardWeek],
        boardOrigin: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ArchiveCalendarWeek] {
        let sortedWeeks = boardWeeks.sorted { $0.startsAt < $1.startsAt }
        guard let rangeStart = boardOrigin ?? sortedWeeks.first?.startsAt,
              let rangeEnd = sortedWeeks.last?.endsAt ?? sortedWeeks.first?.endsAt else {
            return []
        }

        let originDay = boardOrigin.map { calendar.startOfDay(for: $0) }
        let weekLookup = Dictionary(
            sortedWeeks.map { week in
                (
                    BoardSchedule.startOfWeek(containing: week.startsAt, calendar: calendar),
                    week
                )
            },
            uniquingKeysWith: { _, new in new }
        )

        return BoardSchedule.weekStarts(from: rangeStart, through: rangeEnd, calendar: calendar)
            .map { weekStart in
                let days = BoardSchedule.daysInWeek(starting: weekStart, calendar: calendar).map { date in
                    let components = calendar.dateComponents([.day, .month, .year], from: date)
                    return ArchiveCalendarDay(
                        id: calendar.startOfDay(for: date),
                        date: date,
                        dayOfMonth: components.day ?? 0,
                        month: components.month ?? 0,
                        year: components.year ?? 0,
                        isToday: BoardSchedule.isSameDay(date, now, calendar: calendar),
                        isBoardOrigin: originDay.map { BoardSchedule.isSameDay(date, $0, calendar: calendar) } ?? false
                    )
                }

                return ArchiveCalendarWeek(
                    id: weekStart,
                    weekStart: weekStart,
                    days: days,
                    monthSegments: monthSegments(for: days),
                    boardWeek: weekLookup[weekStart]
                )
            }
    }

    private static func monthSegments(for days: [ArchiveCalendarDay]) -> [ArchiveMonthSegment] {
        guard !days.isEmpty else { return [] }

        var segments: [ArchiveMonthSegment] = []
        var currentMonth = days[0].month
        var currentYear = days[0].year
        var count = 0

        for day in days {
            if day.month == currentMonth, day.year == currentYear {
                count += 1
            } else {
                segments.append(ArchiveMonthSegment(month: currentMonth, year: currentYear, dayCount: count))
                currentMonth = day.month
                currentYear = day.year
                count = 1
            }
        }

        segments.append(ArchiveMonthSegment(month: currentMonth, year: currentYear, dayCount: count))
        return segments
    }
}
