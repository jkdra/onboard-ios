//
//  BoardStore+Realtime.swift
//  On Board
//
//  Subscribes to Supabase Realtime postgres changes on `reactions` and
//  merges remote count updates into the local session cache.
//

import Foundation

extension BoardStore {
    func restartReactionRealtime() {
        guard isLive,
              canInteractWithBoard,
              let client = SupabaseClientFactory.client(for: AppConfiguration.current) else {
            Task { await stopReactionRealtime() }
            return
        }

        if reactionRealtimeListener == nil {
            reactionRealtimeListener = ReactionRealtimeListener(client: client)
        }

        reactionRealtimeListener?.start { [weak self] change in
            self?.applyRemoteReactionChange(change)
        }
    }

    func stopReactionRealtime() async {
        await reactionRealtimeListener?.stop()
        reactionRealtimeListener = nil
    }

    func applyRemoteReactionChange(_ change: ReactionRealtimeChange) {
        guard change.userID != currentUserID else { return }
        guard let index = posts.firstIndex(where: { $0.id == change.postID }),
              canInteract(with: posts[index]) else { return }

        if change.previousType == change.newType { return }

        var counts = posts[index].reactionCounts

        if let previous = change.previousType {
            let next = max(0, (counts[previous] ?? 0) - 1)
            if next == 0 {
                counts.removeValue(forKey: previous)
            } else {
                counts[previous] = next
            }
        }

        if let reaction = change.newType {
            counts[reaction, default: 0] += 1
        }

        posts[index].reactionCounts = counts
        patchPostInWeekCache(posts[index])
    }
}
