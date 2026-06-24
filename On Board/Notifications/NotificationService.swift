//
//  NotificationService.swift
//  On Board
//

import Foundation
import Supabase
import UIKit
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private var pendingToken: Data?
    private(set) var currentUserID: UUID?

    private init() {}

    // Called by On_BoardApp when auth session changes to signed-in.
    func onSignedIn(userID: UUID) async {
        currentUserID = userID
        await requestPermissionAndRegister()
        if let token = pendingToken {
            pendingToken = nil
            await upload(tokenData: token, userID: userID)
        }
    }

    func onSignedOut() {
        currentUserID = nil
    }

    // Called by AppDelegate when APNs returns a device token.
    func setPendingToken(_ data: Data) {
        pendingToken = data
        guard let userID = currentUserID else { return }
        let captured = data
        Task { await upload(tokenData: captured, userID: userID) }
    }

    // Call on every app foreground to keep last_seen_at fresh.
    func updateLastSeen(userID: UUID) async {
        guard let client = SupabaseClientFactory.client(for: .current) else { return }
        try? await client
            .from("profiles")
            .update(LastSeenPayload(lastSeenAt: .now))
            .eq("id", value: userID.uuidString)
            .execute()
    }

    // MARK: - Private

    private func requestPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()
        guard let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge]),
              granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func upload(tokenData: Data, userID: UUID) async {
        let hex = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        guard let client = SupabaseClientFactory.client(for: .current) else { return }
        try? await client
            .rpc("register_device_token", params: ["p_token": hex])
            .execute()
    }

    private struct LastSeenPayload: Encodable {
        let lastSeenAt: Date  // encoded as "last_seen_at" by BoardJSON.encoder
    }
}
