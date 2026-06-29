//
//  CountdownCard.swift
//  On Board
//

import SwiftUI

struct CountdownCard: View {
    let week: BoardWeek?
    let isArchived: Bool

    @Environment(BoardStore.self) private var store

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
                    .fontStyle(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("This week's posts are read-only. See what people had to say at the time.")
                .fontStyle(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 200)
        .background(cardBackground())
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
                .fontStyle(.callout)
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
        .frame(minHeight: 200)
        .background(cardBackground(clearingSoon: clearingSoon))
    }

    private func counterColumn(value: Int, label: String, clearingSoon: Bool) -> some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .fontStyle(.title3)
                .foregroundStyle(clearingSoon ? .red : .primary)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.4), value: value)
            Text(label)
                .font(.custom("ZalandoSansSemiExpanded-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(clearingSoon ? .red : .secondary)
        }
    }

    @ViewBuilder
    private func cardBackground(clearingSoon: Bool = false) -> some View {
        let border = clearingSoon ? Color.red.opacity(0.4) : Color.secondary.opacity(0.25)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    clearingSoon ? .regular.tint(Color.red.opacity(0.12)) : .regular,
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(border, lineWidth: 0.9)
                }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(border, lineWidth: 0.9)
                }
        }
    }
}
