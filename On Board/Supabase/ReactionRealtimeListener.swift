//
//  ReactionRealtimeListener.swift
//  On Board
//

import Foundation
import Supabase

@MainActor
final class ReactionRealtimeListener {
    private let client: SupabaseClient
    private var task: Task<Void, Never>?
    private var channel: RealtimeChannelV2?

    init(client: SupabaseClient) {
        self.client = client
    }

    func start(onChange: @escaping @MainActor (ReactionRealtimeChange) -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            await self?.run(onChange: onChange)
        }
    }

    func stop() async {
        task?.cancel()
        task = nil

        if let channel {
            await client.removeChannel(channel)
            self.channel = nil
        }
    }

    private func run(onChange: @escaping @MainActor (ReactionRealtimeChange) -> Void) async {
        await client.realtimeV2.connect()

        let channel = client.channel("board-reactions")
        self.channel = channel

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "reactions"
        )

        try? await channel.subscribeWithError()

        for await change in changes {
            if Task.isCancelled { break }
            guard let parsed = ReactionRealtimeParser.parse(change) else { continue }
            onChange(parsed)
        }

        if let channel = self.channel {
            await client.removeChannel(channel)
            self.channel = nil
        }
    }
}
