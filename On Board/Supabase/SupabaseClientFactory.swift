//
//  SupabaseClientFactory.swift
//  On Board
//
//  Client for the official On Board Supabase project (maintainer-configured keys).
//  Contributors work against mock data and do not need a personal backend.
//

import Foundation
import Supabase

enum SupabaseClientFactory {
    // The client is cached process-wide and built lazily on first use. `client(for:)` is
    // `nonisolated` and is called from several actors (MainActor views, the off-main service
    // initializers, NotificationService), so the cache is guarded by a lock to avoid a data
    // race / double-construction on concurrent first access.
    private nonisolated(unsafe) static var cachedClient: SupabaseClient?
    private nonisolated(unsafe) static var cachedKey: String?
    private nonisolated static let lock = NSLock()

    nonisolated static func client(for configuration: AppConfiguration) -> SupabaseClient? {
        guard configuration.isSupabaseConfigured,
              let url = configuration.supabaseURL,
              let host = url.host,
              !host.isEmpty,
              let key = configuration.supabaseAnonKey else {
            return nil
        }

        let cacheKey = "\(url.absoluteString)|\(key)"

        lock.lock()
        defer { lock.unlock() }

        if cachedKey == cacheKey, let cachedClient {
            return cachedClient
        }

        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                db: .init(
                    encoder: BoardJSON.encoder,
                    decoder: BoardJSON.decoder
                ),
                auth: .init(
                    redirectToURL: AppConfiguration.authRedirectURL,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        cachedKey = cacheKey
        cachedClient = client
        return client
    }
}
