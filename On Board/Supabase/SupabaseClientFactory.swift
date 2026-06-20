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
    private nonisolated(unsafe) static var cachedClient: SupabaseClient?
    private nonisolated(unsafe) static var cachedKey: String?

    nonisolated static func client(for configuration: AppConfiguration) -> SupabaseClient? {
        guard configuration.isSupabaseConfigured,
              let url = configuration.supabaseURL,
              let host = url.host,
              !host.isEmpty,
              let key = configuration.supabaseAnonKey else {
            return nil
        }

        let cacheKey = "\(url.absoluteString)|\(key)"
        if cachedKey == cacheKey, let cachedClient {
            return cachedClient
        }

        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
        cachedKey = cacheKey
        cachedClient = client
        return client
    }
}
