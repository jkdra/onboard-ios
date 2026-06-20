//
//  ArchiveCalendarView.swift
//  On Board
//
//  Vertical Monday-start calendar. Month splits show a divider only (29 30 | 1).
//  Days outside the scroll-focused month fade out.
//

import SwiftUI

private struct WeekScrollPreference: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]

    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ArchiveCalendarView: View {
    let weeks: [ArchiveCalendarWeek]
    @Binding var selectedWeekID: UUID?

    @State private var weekPositions: [Date: CGFloat] = [:]
    @State private var scrollCenterY: CGFloat = 0
    /// Captured once so scroll padding stays stable (avoids layout ↔ scroll feedback loops).
    @State private var layoutViewportHeight: CGFloat = 0
    @State private var focusedMonth: CalendarMonth?

    private let unfocusedOpacity: Double = 0.28
    private let defaultTopPadding: CGFloat = 32
    private let defaultBottomPadding: CGFloat = 120

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    pastBoundaryCap
                        .padding(.top, topScrollPadding)

                    ForEach(weeks) { week in
                        weekRow(for: week)
                            .id(week.id)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: WeekScrollPreference.self,
                                        value: [week.id: geometry.frame(in: .named("archiveScroll")).midY]
                                    )
                                }
                            }
                    }

                    futureBoundaryCap
                        .padding(.bottom, bottomScrollPadding)

                    legend
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .coordinateSpace(name: "archiveScroll")
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    centerY: geometry.contentOffset.y + geometry.containerSize.height / 2,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, metrics in
                if layoutViewportHeight == 0, metrics.viewportHeight > 0 {
                    layoutViewportHeight = metrics.viewportHeight
                }
                scrollCenterY = metrics.centerY
                updateFocusedMonth()
            }
            .onPreferenceChange(WeekScrollPreference.self) { positions in
                guard !positionsApproximatelyEqual(positions, weekPositions) else { return }
                weekPositions = positions
                updateFocusedMonth()
            }
            .onAppear {
                seedFocusedMonthIfNeeded()
                scrollToSelection(with: proxy, animated: false)
            }
            .onChange(of: selectedWeekID) { _, _ in
                scrollToSelection(with: proxy, animated: true)
            }
        }
    }

    // MARK: - Boundary caps

    private var pastBoundaryCap: some View {
        VStack(spacing: 10) {
            dotTrail(fading: .towardContent)
            Text("Looks like that's all!")
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Beginning of the archive. Looks like that's all.")
    }

    private var futureBoundaryCap: some View {
        VStack(spacing: 16) {
            ghostWeekRow(title: "Next Week")
            Text("More weeks to come!")
                .fontStyle(.footnote)
                .foregroundStyle(.tertiary)
            dotTrail(fading: .towardEdge)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Future weeks. Next week. More weeks to come.")
    }

    private enum DotFadeDirection {
        /// Faint at the outer edge, stronger toward the calendar content.
        case towardContent
        /// Strongest near the calendar content, faint toward the outer edge.
        case towardEdge
    }

    private func dotTrail(fading direction: DotFadeDirection) -> some View {
        VStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(dotOpacity(for: index, direction: direction)))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func dotOpacity(for index: Int, direction: DotFadeDirection) -> Double {
        let step = 0.14
        let base = 0.12
        switch direction {
        case .towardContent:
            return base + Double(index) * step
        case .towardEdge:
            return base + Double(2 - index) * step
        }
    }

    private func ghostWeekRow(title: String) -> some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }

            Text("(\(title))")
                .fontStyle(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .allowsHitTesting(false)
    }

    private var topScrollPadding: CGFloat {
        guard layoutViewportHeight > 0 else { return defaultTopPadding }
        return max(defaultTopPadding, layoutViewportHeight * 0.08)
    }

    private var bottomScrollPadding: CGFloat {
        guard layoutViewportHeight > 0 else { return defaultBottomPadding }
        return max(defaultBottomPadding, layoutViewportHeight * 0.22)
    }

    private struct ScrollMetrics: Equatable {
        let centerY: CGFloat
        let viewportHeight: CGFloat
    }

    private func positionsApproximatelyEqual(_ lhs: [Date: CGFloat], _ rhs: [Date: CGFloat]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, value) in lhs {
            guard let other = rhs[key], abs(value - other) < 0.5 else { return false }
        }
        return true
    }

    private func weekRow(for week: ArchiveCalendarWeek) -> some View {
        let isSelected = week.boardWeek.map { selectedWeekID == $0.id } ?? false

        return Button {
            if let boardWeek = week.boardWeek {
                selectedWeekID = boardWeek.id
            }
        } label: {
            HStack(spacing: 0) {
                ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                    if index > 0, crossesMonthBoundary(between: week.days[index - 1], and: day) {
                        monthSplitDivider
                    }
                    dayCell(day)
                }
            }
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .offset(y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(week.boardWeek == nil)
    }

    private var monthSplitDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 32)
    }

    @ViewBuilder
    private func dayCell(_ day: ArchiveCalendarDay) -> some View {
        let inFocus = isInFocus(day)

        ZStack {
            if day.isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .offset(y: -3)
            }

            VStack(spacing: 2) {
                Text("\(day.dayOfMonth)")
                    .fontStyle(.subheadline)
                    .foregroundStyle(day.isToday ? Color.white : .primary)

                if day.isBoardOrigin {
                    Circle()
                        .fill(day.isToday ? Color.white.opacity(0.9) : Color.accentColor)
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
        }
        .opacity(inFocus ? 1 : unfocusedOpacity)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(for: day))
    }

    private var legend: some View {
        HStack(spacing: 20) {
            legendItem(color: Color.accentColor, filled: true, label: "Today")
            legendItem(color: Color.secondary.opacity(0.18), filled: true, label: "Selected week")
            legendItem(color: Color.accentColor, dot: true, label: "Board created")
        }
        .fontStyle(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(color: Color, filled: Bool = false, dot: Bool = false, label: String) -> some View {
        HStack(spacing: 6) {
            if dot {
                Circle().fill(color).frame(width: 6, height: 6)
            } else if filled {
                Circle().fill(color).frame(width: 10, height: 10)
            } else {
                Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 10, height: 10)
            }
            Text(label)
        }
    }

    private func crossesMonthBoundary(between previous: ArchiveCalendarDay, and next: ArchiveCalendarDay) -> Bool {
        previous.month != next.month || previous.year != next.year
    }

    private func isInFocus(_ day: ArchiveCalendarDay) -> Bool {
        guard let focusedMonth else { return true }
        return focusedMonth.contains(day)
    }

    private func seedFocusedMonthIfNeeded() {
        guard focusedMonth == nil else { return }
        if let todayMonth = todayMonth() {
            focusedMonth = todayMonth
        } else if let active = weeks.last?.dominantMonth {
            focusedMonth = active
        }
    }

    private func todayMonth() -> CalendarMonth? {
        let today = Calendar.current.dateComponents([.month, .year], from: .now)
        guard let month = today.month, let year = today.year else { return nil }
        return CalendarMonth(month: month, year: year)
    }

    private func updateFocusedMonth() {
        guard !weekPositions.isEmpty else { return }

        let nearestWeekID = weekPositions.min { lhs, rhs in
            abs(lhs.value - scrollCenterY) < abs(rhs.value - scrollCenterY)
        }?.key

        guard let nearestWeekID,
              let week = weeks.first(where: { $0.id == nearestWeekID }),
              let month = week.dominantMonth else { return }

        if focusedMonth != month {
            focusedMonth = month
        }
    }

    private func dayAccessibilityLabel(for day: ArchiveCalendarDay) -> String {
        var parts = [day.date.formatted(.dateTime.month(.wide).day())]
        if day.isToday { parts.append("today") }
        if day.isBoardOrigin { parts.append("board created") }
        if !isInFocus(day) { parts.append("outside focused month") }
        return parts.joined(separator: ", ")
    }

    private func scrollToSelection(with proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedWeekID,
              let week = weeks.first(where: { $0.boardWeek?.id == selectedWeekID }) else {
            if let activeWeek = weeks.last {
                scroll(to: activeWeek.id, with: proxy, animated: animated)
            }
            return
        }
        scroll(to: week.id, with: proxy, animated: animated)
    }

    private func scroll(to id: Date, with proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.smooth(duration: 0.35)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

#Preview("Month boundary") {
    let calendar = Calendar.current
    let juneWeekStart = calendar.date(from: DateComponents(year: 2025, month: 6, day: 30))!
    let weeks = ArchiveCalendarBuilder.build(
        boardWeeks: [
            BoardWeek(
                startsAt: juneWeekStart,
                endsAt: calendar.date(byAdding: .day, value: 7, to: juneWeekStart)!,
                status: .archived,
                archivedAt: juneWeekStart
            )
        ],
        boardOrigin: calendar.date(from: DateComponents(year: 2025, month: 6, day: 15)),
        now: calendar.date(from: DateComponents(year: 2025, month: 7, day: 2))!
    )

    return ArchiveCalendarView(weeks: weeks, selectedWeekID: .constant(weeks.first?.boardWeek?.id))
}

#Preview("Multiple weeks") {
    @Previewable @State var selected: UUID?
    let store = BoardStore.previewBoard()
    let weeks = ArchiveCalendarBuilder.build(
        boardWeeks: store.boardWeeks,
        boardOrigin: store.currentBoard?.createdAt
    )
    selected = store.activeBoardWeek?.id

    return ArchiveCalendarView(weeks: weeks, selectedWeekID: $selected)
}
