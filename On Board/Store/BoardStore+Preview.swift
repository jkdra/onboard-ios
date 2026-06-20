//
//  BoardStore+Preview.swift
//  On Board
//
//  Preview fixtures and offline development data when Supabase is not configured.
//

import Foundation

extension BoardStore {
    /// Lightweight sample data for previews that only need posts and profiles.
    static func sampleBoard(currentUserID: UUID? = nil) -> BoardStore {
        BoardStore(
            posts: Post.samples,
            profiles: Profile.samples,
            currentUserID: currentUserID
        )
    }

    /// Active week plus archived history — for previews and UI development.
    static func previewBoard(currentUserID: UUID? = SampleProfileID.maya) -> BoardStore {
        let now = Date()
        let mainBoard = Board(
            id: SampleBoardID.main,
            name: "On Board",
            createdAt: now.addingTimeInterval(-86_400 * 38)
        )

        let activeWeek = BoardWeek(
            id: SampleBoardWeekID.active,
            boardId: mainBoard.id,
            startsAt: now.addingTimeInterval(-86_400 * 3),
            endsAt: now.addingTimeInterval(86_400 * 4),
            status: .active
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
        let currentPosts = Array(Post.samples.prefix(4)).map {
            $0.assigning(boardWeekId: activeWeek.id, isReadOnly: false)
        }
        let archivedPosts = Array(Post.samples.suffix(3)).map {
            $0.assigning(boardWeekId: archivedWeeks[0].id, isReadOnly: true)
        }

        return BoardStore(
            posts: currentPosts + archivedPosts,
            profiles: Profile.samples,
            currentUserID: currentUserID,
            activeBoardWeek: activeWeek,
            boardWeeks: allWeeks,
            currentBoard: mainBoard
        )
    }
}
