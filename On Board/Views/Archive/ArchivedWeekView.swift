//
//  ArchivedWeekView.swift
//  On Board
//

import SwiftUI

struct ArchivedWeekView: View {
    let week: BoardWeek

    @Environment(BoardStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    private let weekFormatter: Date.FormatStyle = .dateTime
        .month(.abbreviated)
        .day()
        .year()

    private var navigationTitle: String {
        "\(week.startsAt.formatted(weekFormatter)) – \(week.endsAt.formatted(weekFormatter))"
    }

    var body: some View {
        ScrollView {
            BoardFeedView(items: store.feedItems(for: week))
        }
        .background {
            LinearGradient(
                colors: [
                    Color.gray.opacity(scheme == .light ? 0.25 : 0.20),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadArchivedWeek(week, for: store.currentUserID)
        }
    }
}

#Preview {
    let store = BoardStore.previewBoard()
    let archivedWeek = store.archivedWeeks[0]

    return NavigationStack {
        ArchivedWeekView(week: archivedWeek)
    }
    .environment(store)
}
