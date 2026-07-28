//
//  Debouncer.swift
//  On Board
//
//  Debounces a live-validation lookup (username availability, school email
//  domain lookup) by a fixed delay, cancelling any in-flight check when a
//  newer one starts. Shared scaffolding for
//  OnboardingUsernameStepView.scheduleAvailabilityCheck and
//  OnboardingSchoolEmailStepView.scheduleSchoolLookup — the only real
//  per-field difference is what `perform` looks up and does with the result.
//
//  `perform` should re-check `isStillCurrent` (and `Task.isCancelled`) itself
//  after any `await` inside it — the delay's own check only covers the gap
//  before `perform` starts running. The school lookup does a second awaited
//  call and re-checks staleness again before acting on it, for exactly this
//  reason.
//

import Foundation

@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?

    func schedule(
        delay: Duration = .milliseconds(350),
        isStillCurrent: @escaping () -> Bool,
        perform: @escaping () async -> Void
    ) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, isStillCurrent() else { return }
            await perform()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
