//
//  OnboardingStatusCache.swift
//  On Board
//
//  Persists the last known onboarding step per user so relaunch survives
//  brief offline periods and failed refresh RPCs.
//

import Foundation

enum OnboardingStatusCache {
    private static let keyPrefix = "onboarding.status.v1."

    static func save(_ status: OnboardingStatus, for userID: UUID) {
        guard let data = try? BoardJSON.encoder.encode(status) else { return }
        UserDefaults.standard.set(data, forKey: keyPrefix + userID.uuidString)
    }

    static func load(for userID: UUID) -> OnboardingStatus? {
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + userID.uuidString) else {
            return nil
        }
        return try? BoardJSON.decoder.decode(OnboardingStatus.self, from: data)
    }

    static func clear(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + userID.uuidString)
    }
}
