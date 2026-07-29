//
//  ClearingSoonPrincipal.swift
//  On Board
//

import SwiftUI

/// Compact live countdown for a nav bar's principal slot during the clears-soon
/// window. Ticks each second and mirrors the countdown card's red urgency cue.
/// Shared by the feed (`ContentView`) and the opened post (`PostDetailView`).
struct ClearingSoonPrincipal: View {
    let weekEnd: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let r = BoardSchedule.timeRemaining(weekEnd: weekEnd, from: context.date)
            // Past the deadline the counter would sit on "0m 00s" until the rollover
            // lands, which reads as a hung clock rather than a board mid-change.
            let text: String = if r.totalSeconds <= 0 {
                "Clearing…"
            } else if r.hours > 0 {
                "\(r.hours)h \(String(format: "%02d", r.minutes))m"
            } else {
                "\(r.minutes)m \(String(format: "%02d", r.seconds))s"
            }
            Label(text, systemImage: "clock.badge.exclamationmark")
                .fontStyle(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        }
    }
}
