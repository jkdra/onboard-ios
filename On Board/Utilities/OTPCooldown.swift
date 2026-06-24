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
    private var task: Task<Void, Never>?

    var canResend: Bool { secondsRemaining == 0 }

    func start(duration: Int = 60) {
        task?.cancel()
        secondsRemaining = duration
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
    }
}
