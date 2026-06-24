//
//  ArchiveCalendarView.swift
//  On Board
//
//  Drum-roller archive calendar. Weeks snap to a central capsule viewfinder.
//

import SwiftUI

// Used in .modifier(active:identity:) transitions for the month label slide
private struct SlideFadeModifier: ViewModifier {
    var offsetX: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content.offset(x: offsetX).opacity(opacity)
    }
}

struct ArchiveCalendarView: View {
    let weeks: [ArchiveCalendarWeek]
    @Binding var selectedWeekID: UUID?

    @State private var scrollPosition = ScrollPosition(idType: Date.self)
    @State private var focusedMonth: CalendarMonth?
    @State private var availableHeight: CGFloat = 0
    @State private var monthForward = true

    private let rowHeight: CGFloat = 56   // 44pt cell + 6pt padding × 2

    // Weeks up to and including the active week — no future weeks shown.
    private var displayedWeeks: [ArchiveCalendarWeek] {
        guard let activeIndex = weeks.lastIndex(where: { $0.boardWeek?.status == .active }) else {
            return weeks
        }
        return Array(weeks[...activeIndex])
    }

    private var centeredWeekDate: Date? {
        scrollPosition.viewID(type: Date.self)
            ?? displayedWeeks.first(where: { $0.boardWeek?.id == selectedWeekID })?.id
    }

    private var centeredWeekIndex: Int? {
        guard let d = centeredWeekDate else { return nil }
        return displayedWeeks.firstIndex(where: { $0.id == d })
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let inset = max(0, (geo.size.height - rowHeight) / 2)

            ZStack(alignment: .top) {
                // Capsule viewfinder + scrolling weeks
                ZStack(alignment: .center) {
                    viewfinderHighlight
                    calendarScrollView(inset: inset)
                }

                // Month label (top) + weekday header (just above viewfinder)
                fixedHeaderOverlay(inset: inset)
            }
            .onAppear { availableHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, h in availableHeight = h }
            .onChange(of: availableHeight) { old, new in
                if old == 0, new > 0 { scrollToSelection(animated: false) }
            }
        }
    }

    // MARK: - Viewfinder (capsule)

    @ViewBuilder
    private var viewfinderHighlight: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
                .frame(height: rowHeight)
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
                .frame(height: rowHeight)
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Scroll view

    private func calendarScrollView(inset: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                pastBoundaryCap
                    .padding(.bottom, 20)

                LazyVStack(spacing: 20) {
                    ForEach(displayedWeeks) { week in
                        weekRow(for: week)
                            .id(week.id)
                    }
                }
                .scrollTargetLayout()

                futureBoundaryCap
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .contentMargins(.vertical, inset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .onAppear {
            seedFocusedMonthIfNeeded()
            scrollToSelection(animated: false)
        }
        .onChange(of: scrollPosition.viewID(type: Date.self)) { old, new in
            // Detect scroll direction for the month label transition
            if let old, let new {
                monthForward = new > old
            }
            updateFocusedMonthAndSelection(for: new)
        }
        .onChange(of: selectedWeekID) { _, newVal in
            let currentDate = scrollPosition.viewID(type: Date.self)
            let currentWeek = weeks.first(where: { $0.id == currentDate })
            if currentWeek?.boardWeek?.id != newVal {
                scrollToSelection(animated: true)
            }
        }
    }

    // MARK: - Fixed header overlay

    // Month label sits at the top; weekday header is pinned just above the viewfinder.
    // bottom spacer = inset + rowHeight pushes the weekday header's bottom to the viewfinder's top.
    private func fixedHeaderOverlay(inset: CGFloat) -> some View {
        VStack(spacing: 0) {
            monthLabelView
                .padding(.horizontal, 20)

            Spacer()

            ArchiveWeekdayHeader()
                .padding(.horizontal, 20)
                .padding(.vertical, 6)

            Color.clear.frame(height: inset + rowHeight)
        }
        .background(alignment: .top) {
            ArchiveToolbarChrome()
                .frame(height: 96)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Month label

    private var monthLabelText: String {
        guard let week = weeks.first(where: { $0.id == centeredWeekDate }) else {
            guard let m = focusedMonth else { return "" }
            return fullMonthName(m.month, year: m.year)
        }

        if week.spansMonthBoundary, week.monthSegments.count >= 2 {
            let a = week.monthSegments[0]
            let b = week.monthSegments[1]
            return "\(shortMonthName(a.month))  |  \(fullMonthName(b.month, year: b.year))"
        }

        if let seg = week.monthSegments.first {
            return fullMonthName(seg.month, year: seg.year)
        }
        return ""
    }

    // Direction-aware transition: forward → slides left/right; backward → opposite
    private var monthLabelTransition: AnyTransition {
        let x: CGFloat = monthForward ? 16 : -16
        return .asymmetric(
            insertion: .modifier(
                active: SlideFadeModifier(offsetX: x, opacity: 0),
                identity: SlideFadeModifier(offsetX: 0, opacity: 1)
            ),
            removal: .modifier(
                active: SlideFadeModifier(offsetX: -x, opacity: 0),
                identity: SlideFadeModifier(offsetX: 0, opacity: 1)
            )
        )
    }

    private var monthLabelView: some View {
        Text(monthLabelText)
            .fontStyle(.headline)
            .foregroundStyle(.primary)
            .id(monthLabelText)
            .transition(monthLabelTransition)
            .animation(.snappy(duration: 0.2), value: monthLabelText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func fullMonthName(_ month: Int, year: Int) -> String {
        var comps = DateComponents()
        comps.month = month; comps.year = year; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return "" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func shortMonthName(_ month: Int) -> String {
        Calendar.current.shortStandaloneMonthSymbols[month - 1]
    }

    // MARK: - Week row

    // Exponential fade: centered = 1.0, each step away multiplies by ~0.55
    private func weekOpacity(for week: ArchiveCalendarWeek) -> Double {
        guard let centeredIndex = centeredWeekIndex,
              let selfIndex = displayedWeeks.firstIndex(where: { $0.id == week.id }) else { return 0.45 }
        let distance = abs(centeredIndex - selfIndex)
        return max(0.10, pow(0.55, Double(distance)))
    }

    private func weekRow(for week: ArchiveCalendarWeek) -> some View {
        let isCentered = week.id == centeredWeekDate

        return Button {
            guard week.boardWeek != nil else { return }
            withAnimation(.smooth(duration: 0.35)) {
                scrollPosition = ScrollPosition(id: week.id, anchor: .center)
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
            .background(Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(week.boardWeek == nil)
        .opacity(weekOpacity(for: week))
        .animation(.smooth(duration: 0.22), value: centeredWeekDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekAccessibilityLabel(for: week))
        .accessibilityAddTraits(isCentered ? [.isSelected] : [])
        .accessibilityHint(
            week.boardWeek == nil ? "No data for this period" :
            week.boardWeek?.status == .active ? "Current week" : "Tap to view"
        )
    }

    private func weekAccessibilityLabel(for week: ArchiveCalendarWeek) -> String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        guard let first = week.days.first, let last = week.days.last else { return "Unknown week" }
        let range = "\(first.date.formatted(fmt)) to \(last.date.formatted(fmt))"
        if week.boardWeek?.status == .active { return "\(range), current week" }
        return range
    }

    private var monthSplitDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 32)
    }

    // MARK: - Day cell (opacity handled at row level)

    private func dayCell(_ day: ArchiveCalendarDay) -> some View {
        ZStack {
            if day.isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .offset(y: -3)
            }
            Text("\(day.dayOfMonth)")
                .fontStyle(.subheadline)
                .foregroundStyle(day.isToday ? Color.white : .primary)
                .offset(y: -3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    // MARK: - Boundary caps

    private var pastBoundaryCap: some View {
        VStack(spacing: 8) {
            dotTrail(ascending: true)
            Text("That's the beginning!")
                .fontStyle(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: rowHeight)
        .opacity(0.65)
        .accessibilityLabel("Beginning of the archive.")
    }

    private var futureBoundaryCap: some View {
        VStack(spacing: 8) {
            dotTrail(ascending: false)
            Text("More weeks to come.")
                .fontStyle(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: rowHeight)
        .opacity(0.65)
        .accessibilityLabel("More weeks to come.")
    }

    private func dotTrail(ascending: Bool) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(ascending ? 0.12 + Double(i) * 0.12 : 0.36 - Double(i) * 0.12))
                    .frame(width: 4, height: 4)
            }
        }
    }

    // MARK: - Scroll helpers

    private func scrollToSelection(animated: Bool) {
        guard let targetID = scrollTargetWeekID() else { return }
        let pos = ScrollPosition(id: targetID, anchor: .center)
        if animated {
            withAnimation(.smooth(duration: 0.35)) { scrollPosition = pos }
        } else {
            scrollPosition = pos
        }
    }

    private func scrollTargetWeekID() -> Date? {
        if let selectedWeekID,
           let match = displayedWeeks.first(where: { $0.boardWeek?.id == selectedWeekID }) {
            return match.id
        }
        return displayedWeeks.last?.id
    }

    private func updateFocusedMonthAndSelection(for weekDate: Date?) {
        guard let weekDate, let week = weeks.first(where: { $0.id == weekDate }) else { return }

        if let boardWeek = week.boardWeek, selectedWeekID != boardWeek.id {
            selectedWeekID = boardWeek.id
        }

        guard let month = week.dominantMonth, focusedMonth != month else { return }
        withAnimation(.snappy(duration: 0.2)) { focusedMonth = month }
    }

    private func seedFocusedMonthIfNeeded() {
        guard focusedMonth == nil else { return }
        let comps = Calendar.current.dateComponents([.month, .year], from: .now)
        if let m = comps.month, let y = comps.year {
            focusedMonth = CalendarMonth(month: m, year: y)
        } else {
            focusedMonth = displayedWeeks.last?.dominantMonth
        }
    }

    private func crossesMonthBoundary(between prev: ArchiveCalendarDay, and next: ArchiveCalendarDay) -> Bool {
        prev.month != next.month || prev.year != next.year
    }
}

// MARK: - Previews

#Preview("Month boundary") {
    let cal = Calendar.current
    let start = cal.date(from: DateComponents(year: 2025, month: 6, day: 30))!
    let weeks = ArchiveCalendarBuilder.build(
        boardWeeks: [
            BoardWeek(
                startsAt: start,
                endsAt: cal.date(byAdding: .day, value: 7, to: start)!,
                status: .archived,
                archivedAt: start
            )
        ],
        boardOrigin: cal.date(from: DateComponents(year: 2025, month: 6, day: 15)),
        now: cal.date(from: DateComponents(year: 2025, month: 7, day: 2))!
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
