//
//  CountdownCard.swift
//  On Board
//

import SwiftUI
import UIKit

struct CountdownCard: View {
    let week: BoardWeek?
    let isArchived: Bool
    var columnWidth: CGFloat = 0

    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("profanityEnabled") private var profanityEnabled = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var triggerShake = 0

    private var currentPromptText: String? {
        let activeWeek = week ?? store.activeBoardWeek
        if profanityEnabled, let profane = activeWeek?.promptProfane, !profane.trimmed.isEmpty {
            return profane
        } else if let clean = activeWeek?.promptClean, !clean.trimmed.isEmpty {
            return clean
        }
        return nil
    }

    private var cardHeight: CGFloat {
        if typeSize.isAccessibilitySize { return 300 }
        let idealHeight = columnWidth * 1.15
        return max(180, min(idealHeight, 260))
    }

    private let weekFormatter: Date.FormatStyle = .dateTime
        .month(.abbreviated)
        .day()

    var body: some View {
        Group {
            if isArchived { archivedNotice }
            else {
                // Tick once a minute for most of the week; only drop to a 1s cadence
                // inside the final 3 hours, where the seconds counter is actually shown.
                // Avoids an all-week per-second view rebuild (battery/CPU) for a display
                // that otherwise only changes each minute.
                TimelineView(.periodic(from: .now, by: 60)) { minuteContext in
                    let weekEnd = week?.endsAt ?? store.activeBoardWeek?.endsAt
                    let remaining = BoardSchedule.timeRemaining(weekEnd: weekEnd, from: minuteContext.date)
                    if remaining.totalSeconds <= 10800 {
                        TimelineView(.periodic(from: .now, by: 1)) { secondContext in
                            activeCountdown(now: secondContext.date)
                        }
                    } else { activeCountdown(now: minuteContext.date) }
                }
            }
        }
        .keyframeAnimator(initialValue: Double(0), trigger: triggerShake) { content, wobble in
            content.rotationEffect(.degrees(wobble))
        } keyframes: { _ in
            CubicKeyframe(2.5, duration: 0.04)
            CubicKeyframe(-2.5, duration: 0.05)
            CubicKeyframe(1.5, duration: 0.05)
            CubicKeyframe(-1.5, duration: 0.05)
            CubicKeyframe(0, duration: 0.05)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            triggerShake += 1
            if hapticsEnabled {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    }

    private var archivedNotice: some View {
        let text = currentPromptText ?? "There was no pompt that week! Let's see what people shared..."
        
        return ZStack(alignment: .bottomTrailing) {
            Image("OBLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .opacity(0.12)
                .offset(x: 8, y: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .fontStyle(.callout)
                    .fontWeight(currentPromptText != nil ? .medium : .regular)
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 0)
                
                VStack(alignment: .leading, spacing: 4) {
                    if let week {
                        Text("\(week.startsAt.formatted(weekFormatter)) – \(week.endsAt.formatted(weekFormatter))".uppercased())
                            .fontStyle(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 16))
                        Text("Archived")
                            .fontStyle(.title3)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: cardHeight)
        .background(cardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func countdownConfig(remaining: TimeInterval) -> (bodyText: String, caption: String, showRed: Bool, isPrompt: Bool) {
        let is24Hours = remaining <= 86400
        let is3Hours = remaining <= 10800
        
        let caption: String
        let showRed: Bool
        if is3Hours {
            caption = "Clears soon!"
            showRed = true
        } else if is24Hours {
            caption = "Clears tonight!"
            showRed = false
        } else {
            caption = "Clears Monday"
            showRed = false
        }
        
        if let prompt = currentPromptText {
            return (prompt, caption, showRed, true)
        } else {
            let defaultText = "No prompt this week! Get creative!"
            return (defaultText, caption, showRed, false)
        }
    }

    @ViewBuilder
    private func activeCountdown(now: Date) -> some View {
        let weekEnd = week?.endsAt ?? store.activeBoardWeek?.endsAt
        let remaining = BoardSchedule.timeRemaining(weekEnd: weekEnd, from: now)
        let is3Hours = remaining.totalSeconds <= 10800
        let config = countdownConfig(remaining: remaining.totalSeconds)

        ZStack(alignment: .bottomTrailing) {
            Image("OBLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .opacity(0.12)
                .offset(x: 8, y: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(config.bodyText)
                    .fontStyle(.callout)
                    .fontWeight(config.isPrompt ? .medium : .regular)
                    .foregroundStyle(.primary) // Higher opacity
                
                Spacer(minLength: 0)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.caption.uppercased())
                        .fontStyle(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(config.showRed ? .red : .secondary)
                    
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
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: cardHeight)
        .background(cardBackground(showRed: config.showRed))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
