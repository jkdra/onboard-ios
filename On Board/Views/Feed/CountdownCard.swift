//
//  CountdownCard.swift
//  On Board
//

import SwiftUI

struct CountdownCard: View {
    let week: BoardWeek?
    let isArchived: Bool
    var columnWidth: CGFloat = 0

    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    private var cardHeight: CGFloat {
        if typeSize.isAccessibilitySize { return 300 }
        let idealHeight = columnWidth * 1.15
        return max(180, min(idealHeight, 260))
    }

    private let weekFormatter: Date.FormatStyle = .dateTime
        .month(.abbreviated)
        .day()

    var body: some View {
        if isArchived {
            archivedNotice
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
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
        .frame(height: cardHeight)
        .background(cardBackground())
    }

    private func countdownConfig(remaining: TimeInterval) -> (title: String, bodyText: String, showRed: Bool) {
        let is12Hours = remaining <= 43200
        let is3Hours = remaining <= 10800
        
        if is3Hours {
            return ("Clears soon!", "The board's about to clear! Last chance to react and comment!", true)
        } else if is12Hours {
            return ("Clears tonight!", "The board clears tonight. Get your final posts in before the reset.", false)
        } else {
            return ("Clears Monday", "The board resets every monday at midnight.", false)
        }
    }

    @ViewBuilder
    private func activeCountdown(now: Date) -> some View {
        let weekEnd = week?.endsAt ?? store.activeBoardWeek?.endsAt
        let remaining = BoardSchedule.timeRemaining(weekEnd: weekEnd, from: now)
        let is3Hours = remaining.totalSeconds <= 10800
        let config = countdownConfig(remaining: remaining.totalSeconds)

        VStack(alignment: .leading, spacing: 8) {
            Text(config.title)
                .fontStyle(.title3)
                .fontWeight(.heavy)
                .foregroundStyle(.primary)
            Text(config.bodyText)
                .fontStyle(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 10) {
                if !is3Hours {
                    counterColumn(value: remaining.days, label: "d", showRed: config.showRed)
                }
                counterColumn(value: remaining.hours, label: "h", showRed: config.showRed)
                counterColumn(value: remaining.minutes, label: "m", showRed: config.showRed)
                if is3Hours {
                    counterColumn(value: remaining.seconds, label: "s", showRed: config.showRed)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight)
        .background(cardBackground(showRed: config.showRed))
    }

    private func counterColumn(value: Int, label: String, showRed: Bool) -> some View {
        let displayValue = label == "d" ? "\(value)" : String(format: "%02d", value)
        return HStack(spacing: 2) {
            Text(displayValue)
                .fontStyle(.title3)
                .foregroundStyle(showRed ? .red : .primary)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.4), value: value)
            Text(label)
                .font(.custom("ZalandoSansSemiExpanded-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(showRed ? .red : .secondary)
        }
    }

    @ViewBuilder
    private func cardBackground(showRed: Bool = false) -> some View {
        let border = showRed ? Color.red.opacity(0.4) : Color.secondary.opacity(0.25)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    showRed ? .regular.tint(Color.red.opacity(0.12)) : .regular,
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
