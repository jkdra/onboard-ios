//
//  BoardStore+Preview.swift
//  On Board
//
//  Preview fixtures and offline development data when Supabase is not configured.
//

import Foundation

extension BoardStore {
    /// A handful of profiles the current user already follows, so the follow
    /// graph (and the feed's followed-post treatment) has something to show
    /// out of the box instead of starting completely empty.
    private static let sampleFollowedUserIDs: Set<UUID> = [
        SampleProfileID.leo, SampleProfileID.sara, SampleProfileID.kevin, SampleProfileID.nora,
    ]

    /// Lightweight sample data for previews that only need posts and profiles.
    static func sampleBoard(currentUserID: UUID? = nil) -> BoardStore {
        let store = BoardStore(
            posts: Post.samples,
            profiles: Profile.samples,
            currentUserID: currentUserID
        )
        store.followedUserIDs = sampleFollowedUserIDs
        return store
    }

    /// Active week plus archived history — for previews and UI development.
    static func previewBoard(currentUserID: UUID? = nil) -> BoardStore {
        let currentUserID = currentUserID ?? SampleProfileID.maya
        let now = Date()
        let mainBoard = Board(
            id: SampleBoardID.main,
            name: "Preview Campus",
            createdAt: now.addingTimeInterval(-86_400 * 38)
        )

        let weekStart = BoardSchedule.startOfWeek(containing: now)
        let nextWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(86_400 * 7)
        let activeWeek = BoardWeek(
            id: SampleBoardWeekID.active,
            boardId: mainBoard.id,
            startsAt: weekStart,
            endsAt: nextWeekStart,
            status: .active,
            promptClean: "What's the best album you've listened to this week?",
            promptProfane: "What's the most badass album you've listened to this week?"
        )

        let archivedWeeks: [BoardWeek] = [
            (-10, -3, SampleBoardWeekID.archived),
            (-17, -10, UUID(uuidString: "B0000000-0000-4000-8000-000000000003")!),
            (-24, -17, UUID(uuidString: "B0000000-0000-4000-8000-000000000004")!),
            (-31, -24, UUID(uuidString: "B0000000-0000-4000-8000-000000000005")!),
        ].map { offset, end, id in
            BoardWeek(
                id: id,
                boardId: mainBoard.id,
                startsAt: now.addingTimeInterval(86_400 * Double(offset)),
                endsAt: now.addingTimeInterval(86_400 * Double(end)),
                status: .archived,
                archivedAt: now.addingTimeInterval(86_400 * Double(end))
            )
        }

        let allWeeks = archivedWeeks + [activeWeek]
        let currentPosts = Array(Post.samples.prefix(12)).map {
            $0.assigning(boardWeekId: activeWeek.id, isReadOnly: false)
        }
        // Spread the remaining posts across every archived week (2/2/1/1) instead of
        // dumping them all into the most recent one — otherwise the Archive list shows
        // three empty weeks, which looks broken rather than just quiet.
        let remainingPosts = Array(Post.samples.suffix(6))
        let archivedGroupSizes = [2, 2, 1, 1]
        var archivedPosts: [Post] = []
        var cursor = 0
        for (week, size) in zip(archivedWeeks, archivedGroupSizes) {
            for post in remainingPosts[cursor..<min(cursor + size, remainingPosts.count)] {
                archivedPosts.append(post.assigning(boardWeekId: week.id, isReadOnly: true))
            }
            cursor += size
        }

        let store = BoardStore(
            posts: currentPosts + archivedPosts,
            profiles: Profile.samples,
            currentUserID: currentUserID,
            activeBoardWeek: activeWeek,
            boardWeeks: allWeeks,
            currentBoard: mainBoard
        )
        store.followedUserIDs = sampleFollowedUserIDs
        return store
    }
}
