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
        let postCount = store.posts(for: week).count
        let fmt: Date.FormatStyle = .dateTime.month(.abbreviated).day()
        let dateRange = "\(week.startsAt.formatted(fmt)) – \(week.endsAt.formatted(fmt))"

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Label(dateRange, systemImage: "calendar")

                if postCount > 0 || week.status == .archived {
                    Divider().frame(height: 12)
                    Label(postCount == 1 ? "1 post" : "\(postCount) posts", systemImage: "doc.text")
                }
            }
            .fontStyle(.footnote)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            if week.status == .active {
                Button {
                    dismiss()
                } label: {
                    Label("Back to This Week", systemImage: "arrow.left.circle.fill")
                }
                .buttonStyle(.boardSecondary)
            } else {
                NavigationLink(value: BoardRoute.archivedWeek(week)) {
                    Label("Open Week", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.boardSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
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
