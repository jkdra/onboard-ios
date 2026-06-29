//
//  ArchiveView.swift
//  On Board
//

import SwiftUI

struct ArchiveView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        Group {
            if store.currentBoardWeeks.allSatisfy({ $0.status == .active }) {
                ContentUnavailableView(
                    "No weeks yet",
                    systemImage: "archivebox",
                    description: Text("Past weeks will show up here after the weekly reset.")
                )
            } else {
                ArchiveCalendarView(weeks: store.currentBoardWeeks)
            }
        }
        .navigationTitle("Archive")
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
