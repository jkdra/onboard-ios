//
//  CountdownCard.swift
//  On Board
//

import SwiftUI

struct CountdownCard: View {
    let week: BoardWeek?
    let isArchived: Bool

    @Environment(BoardStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    private let weekFormatter: Date.FormatStyle = .dateTime
        .month(.abbreviated)
        .day()

    var body: some View {
        if isArchived {
            archivedNotice
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                activeCountdown(now: context.date)
            }
        }
    }

    private var archivedNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Archived week", systemImage: "archivebox")
                .fontStyle(.title3)
                .fontWeight(.heavy)
                .foregroundStyle(.secondary)

            if let week {
                Text("\(week.startsAt.formatted(weekFormatter)) – \(week.endsAt.formatted(weekFormatter))")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("This week's posts are read-only. See what people had to say at the time.")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 200)
        .background(cardBackground)
    }

    @ViewBuilder
    private func activeCountdown(now: Date) -> some View {
        let weekEnd = week?.endsAt ?? store.activeBoardWeek?.endsAt
        let clearingSoon = BoardSchedule.isClearingSoon(weekEnd: weekEnd, from: now)
        let remaining = BoardSchedule.timeRemaining(weekEnd: weekEnd, from: now)

        VStack(alignment: .leading, spacing: 8) {
            Text(!clearingSoon ? "Clears Monday" : "Clears tonight!")
                .fontStyle(.title3)
                .fontWeight(.heavy)
                .foregroundStyle(.primary)
            Text(!clearingSoon ? "The board resets every monday at midnight." : "The board's clearing tonight! Last chance to post and comment!")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !clearingSoon {
                    counterColumn(value: remaining.days, label: "d", clearingSoon: clearingSoon)
                }
                counterColumn(value: remaining.hours, label: "h", clearingSoon: clearingSoon)
                counterColumn(value: remaining.minutes, label: "m", clearingSoon: clearingSoon)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 200)
        .background(cardBackground)
    }

    private func counterColumn(value: Int, label: String, clearingSoon: Bool) -> some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .fontStyle(.title3)
                .foregroundStyle(clearingSoon ? .red : .primary)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.4), value: value)
            Text(label)
                .fontStyle(.subheadline)
                .foregroundStyle(clearingSoon ? .red : .secondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.gray.opacity(scheme == .dark ? 0.30 : 0.22))
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.45 : 0.18),
                radius: 10,
                x: 0,
                y: 6
            )
    }
}
