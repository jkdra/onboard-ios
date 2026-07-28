//
//  NotificationService.swift
//  On Board
//

import Foundation
import Observation
import Supabase
import UIKit
import UserNotifications

@Observable
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    @ObservationIgnored private var pendingToken: Data?
    private(set) var currentUserID: UUID?
    /// The hex APNs token last registered for the signed-in user, so a sign-out (which
    /// doesn't delete the account, unlike account deletion's `ON DELETE CASCADE`) can
    /// unregister this device from that account's push notifications.
    private(set) var currentTokenHex: String?

    /// Post to open when the user tapped a notification. Stashed here (same
    /// idiom as `pendingToken`) because the tap can arrive on a cold launch,
    /// long before the feed exists or posts are fetched — ContentView consumes
    /// it once the post is available.
    private(set) var pendingPostID: UUID?

    /// Profile to open from a shared profile link, same idiom as `pendingPostID`.
    private(set) var pendingProfileID: UUID?

    private init() {}

    // Called by AppDelegate when the user taps a notification. Payloads for
    // reaction/comment/digest pushes carry a `post_id`; board-wide pushes
    // (monday-reset, re-engagement) don't — those just open the app.
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let idString = userInfo["post_id"] as? String,
              let postID = UUID(uuidString: idString) else { return }
        pendingPostID = postID
    }

    func clearPendingPostID() {
        pendingPostID = nil
    }

    func setPendingPostID(_ id: UUID) {
        pendingPostID = id
    }

    func clearPendingProfileID() {
        pendingProfileID = nil
    }

    func setPendingProfileID(_ id: UUID) {
        pendingProfileID = id
    }

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
        currentTokenHex = nil
    }

    // Called by AppDelegate when APNs returns a device token.
    func setPendingToken(_ data: Data) {
        pendingToken = data
        guard let userID = currentUserID else { return }
        let captured = data
        Task { await upload(tokenData: captured, userID: userID) }
    }

    func clearBadge() {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    // Call on every app foreground to keep last_seen_at fresh.
    func updateLastSeen(userID: UUID) async {
        guard let client = SupabaseClientFactory.client(for: .current) else { return }
        _ = try? await client
            .from("profiles")
            .update(LastSeenPayload(lastSeenAt: .now))
            .eq("id", value: userID.uuidString)
            .execute()
    }

    // MARK: - Private

    private func requestPermissionAndRegister() async {
        // UI-test runs pass `-dev.skipPushPrompt`: the system permission alert lands on
        // an unpredictable frame (it waits on the first APNs touch, not launch), and a
        // springboard alert that appears mid-walkthrough swallows the taps under it.
        guard !ProcessInfo.processInfo.arguments.contains("-dev.skipPushPrompt") else { return }
        let center = UNUserNotificationCenter.current()
        guard let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge]),
              granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func upload(tokenData: Data, userID: UUID) async {
        // The upload is scheduled asynchronously from setPendingToken/onSignedIn;
        // on a fast sign-out→sign-in the active user can change before it runs.
        // Bail if this token is no longer for the current session so we don't
        // register the device against the wrong account.
        guard currentUserID == userID else { return }
        let hex = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        currentTokenHex = hex
        guard let client = SupabaseClientFactory.client(for: .current) else { return }
        _ = try? await client
            .rpc("register_device_token", params: ["p_token": hex])
            .execute()
    }

    private struct LastSeenPayload: Encodable {
        let lastSeenAt: Date  // encoded as "last_seen_at" by BoardJSON.encoder
    }
}
