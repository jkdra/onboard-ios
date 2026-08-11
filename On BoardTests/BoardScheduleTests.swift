//
//  BoardScheduleTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct BoardScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func clearingSoonWithinFinalThreeHours() {
        let sundayNight = date(year: 2025, month: 6, day: 15, hour: 21, minute: 30)
        #expect(BoardSchedule.isClearingSoon(from: sundayNight, calendar: calendar))
    }

    @Test func notClearingSoonOutsideFinalThreeHours() {
        let sundayMorning = date(year: 2025, month: 6, day: 15, hour: 6)
        #expect(!BoardSchedule.isClearingSoon(from: sundayMorning, calendar: calendar))
    }

    @Test func timeRemainingBreaksDownIntoDaysHoursMinutes() {
        let saturdayNight = date(year: 2025, month: 6, day: 14, hour: 21, minute: 30)
        let remaining = BoardSchedule.timeRemaining(from: saturdayNight, calendar: calendar)
        #expect(remaining.days == 1)
        #expect(remaining.hours == 2)
        #expect(remaining.minutes == 30)
    }
}
