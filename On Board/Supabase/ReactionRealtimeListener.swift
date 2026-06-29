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
        // Tear down any prior channel before the new run() creates one, so two
        // identically-named channels never coexist on a rapid restart.
        task?.cancel()
        let previousChannel = channel
        channel = nil
        task = Task { [weak self] in
            if let previousChannel { await self?.client.removeChannel(previousChannel) }
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
        // Reconnect loop: the postgresChange stream ends when the socket drops (network
        // blip, app backgrounded). Without this the listener died permanently after the
        // first disconnect and reaction counts silently stopped updating.
        while !Task.isCancelled {
            await client.realtimeV2.connect()

            let channel = client.channel("board-reactions")
            self.channel = channel

            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "reactions"
            )

            do {
                try await channel.subscribeWithError()
            } catch {
                await client.removeChannel(channel)
                if self.channel === channel { self.channel = nil }
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            for await change in changes {
                if Task.isCancelled { break }
                guard let parsed = ReactionRealtimeParser.parse(change) else { continue }
                onChange(parsed)
            }

            // Clean up THIS channel (not self.channel, which a concurrent start() may have
            // already replaced) before deciding whether to reconnect.
            await client.removeChannel(channel)
            if self.channel === channel { self.channel = nil }

            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(2)) // backoff, then reconnect
        }
    }
}
