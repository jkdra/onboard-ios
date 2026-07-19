//
//  ArchivedWeekView.swift
//  On Board
//

import SwiftUI

struct ArchivedWeekView: View {
    let week: BoardWeek

    @Environment(BoardStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var hasLoaded = false

    private let weekFormatter: Date.FormatStyle = .dateTime
        .month(.abbreviated)
        .day()
        .year()

    private var navigationTitle: String {
        "\(week.startsAt.formatted(weekFormatter)) – \(week.endsAt.formatted(weekFormatter))"
    }

    /// A revisit hits the warm archive cache synchronously, so we can show the
    /// real feed on first render with no skeleton flash; a cold week shows the
    /// skeleton until `.task`'s load resolves.
    private var isReady: Bool {
        hasLoaded || store.cachedArchiveWeekIDs.contains(week.id)
    }

    var body: some View {
        ScrollView {
            if isReady {
                BoardFeedView(items: store.feedItems(for: week))
            } else {
                FeedSkeletonView()
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isReady)
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
            hasLoaded = true
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
