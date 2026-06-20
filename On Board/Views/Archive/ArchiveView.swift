//
//  ArchiveView.swift
//  On Board
//

import SwiftUI

struct ArchiveView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) var dismiss

    @State private var selectedWeekID: UUID?
    @State private var calendarWeeks: [ArchiveCalendarWeek] = []
    @State private var calendarCacheKey = ""

    private var timelineWeeks: [BoardWeek] {
        guard let boardID = store.currentBoardId else { return store.boardWeeks }
        return store.boardWeeks
            .filter { $0.boardId == boardID }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var boardOriginDate: Date? {
        store.currentBoard?.createdAt ?? timelineWeeks.first?.startsAt
    }

    private var calendarWeeksCacheKey: String {
        let weeks = timelineWeeks
            .map { "\($0.id.uuidString):\($0.status.rawValue)" }
            .joined(separator: "|")
        let origin = boardOriginDate?.timeIntervalSince1970 ?? 0
        return "\(store.currentBoardId?.uuidString ?? "none")|\(weeks)|\(origin)"
    }

    var body: some View {
        Group {
            if calendarWeeks.isEmpty {
                ContentUnavailableView(
                    "No weeks yet",
                    systemImage: "archivebox",
                    description: Text("Past weeks will show up here after the weekly reset.")
                )
            } else {
                ArchiveCalendarView(
                    weeks: calendarWeeks,
                    selectedWeekID: $selectedWeekID
                )
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            ArchiveWeekdayHeader()
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background {
                    if #available(iOS 26.0, *) {
                        Capsule()
                            .foregroundStyle(.clear)
                            .glassEffect(.regular, in: .capsule(style: .circular))
                    } else {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .horizontal)
                    }
                }
                .safeAreaPadding(.horizontal)
                
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selectedWeek = selectedBoardWeek {
                weekFooter(for: selectedWeek)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            rebuildCalendarWeeksIfNeeded()
            if selectedWeekID == nil {
                selectedWeekID = store.activeBoardWeek?.id
            }
        }
        .onChange(of: calendarWeeksCacheKey) { _, _ in
            rebuildCalendarWeeksIfNeeded()
        }
    }

    private func rebuildCalendarWeeksIfNeeded() {
        let key = calendarWeeksCacheKey
        guard key != calendarCacheKey else { return }
        calendarWeeks = ArchiveCalendarBuilder.build(
            boardWeeks: timelineWeeks,
            boardOrigin: boardOriginDate
        )
        calendarCacheKey = key
    }

    private var selectedBoardWeek: BoardWeek? {
        guard let selectedWeekID else { return nil }
        return timelineWeeks.first { $0.id == selectedWeekID }
    }

    @ViewBuilder
    private func weekFooter(for week: BoardWeek) -> some View {
        VStack(spacing: 12) {
            Text(weekSummary(for: week))
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Group {
                if week.status == .active {
                    Button {
                        dismiss()
                    } label: {
                        Label(openWeekLabel(for: week), systemImage: "arrow.left.circle.fill")
                    }
                } else {
                    NavigationLink(value: BoardRoute.archivedWeek(week)) {
                        Label(openWeekLabel(for: week), systemImage: "arrow.right.circle.fill")
                    }
                }
            }
            .buttonStyle(.boardSecondary)
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func weekSummary(for week: BoardWeek) -> String {
        let posts = store.posts(for: week).count
        let formatter: Date.FormatStyle = .dateTime.month(.abbreviated).day()
        let start = week.startsAt.formatted(formatter)
        let end = week.endsAt.formatted(formatter)
        let status = week.status == .active ? "This week" : "Archived"
        return "\(status) · \(start) – \(end) · \(posts) posts"
    }

    private func openWeekLabel(for week: BoardWeek) -> String {
        week.status == .active ? "Back to This Week" : "Open Week"
    }
}

#Preview {
    NavigationStack {
        ArchiveView()
            .navigationDestination(for: BoardRoute.self) { route in
                switch route {
                case .archive:
                    ArchiveView()
                case .archivedWeek(let week):
                    ArchivedWeekView(week: week)
                case .post(let postID):
                    if let post = BoardStore.previewBoard().post(with: postID) {
                        PostDetailView(post: post)
                    }
                case .profile(let profile):
                    ProfileView(profile: profile, presentation: .navigation)
                }
            }
    }
    .environment(BoardStore.previewBoard())
}
