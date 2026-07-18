//
//  OTPCooldown.swift
//  On Board
//

import Foundation
import Observation

@Observable
@MainActor
final class OTPCooldown {
    private(set) var secondsRemaining = 0
    /// Where the last code went. Lets `canSend(to:)` distinguish "same address,
    /// still in the window — reuse the in-flight code" from "new address —
    /// send freely". Survives `reset()`-free view state teardowns (backing out
    /// of the OTP screen must NOT re-arm sending to the same destination).
    private(set) var lastDestination: String?
    private var task: Task<Void, Never>?

    var canResend: Bool { secondsRemaining == 0 }

    /// Whether a fresh code may be sent to `destination`: the window has
    /// expired, or the destination differs from the last send (a new address
    /// never has a valid code in flight, so it may always be sent to).
    func canSend(to destination: String) -> Bool {
        canResend || destination != lastDestination
    }

    func start(duration: Int = 60, destination: String? = nil) {
        task?.cancel()
        secondsRemaining = duration
        lastDestination = destination
        task = Task {
            for remaining in stride(from: duration - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                secondsRemaining = remaining
            }
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        secondsRemaining = 0
        lastDestination = nil
    }
}
