import SwiftUI

@MainActor
@Observable
final class CropInteractionState {
    var isBlurRemoved = false
    private var autoSettleTask: Task<Void, Never>?
    
    func cancelAutoSettle() {
        autoSettleTask?.cancel()
        autoSettleTask = nil
    }
    
    func notifyInteractionStarted() {
        cancelAutoSettle()
        if !isBlurRemoved {
            withAnimation(.easeOut(duration: 0.2)) {
                isBlurRemoved = true
            }
        }
    }
    
    func scheduleAutoSettle(
        delay: Duration = .milliseconds(1_500),
        animation: Animation = .easeInOut(duration: 0.3),
        onSettle: @escaping @MainActor () -> Void = {}
    ) {
        cancelAutoSettle()
        autoSettleTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            onSettle()
            withAnimation(animation) {
                isBlurRemoved = false
            }
        }
    }
}
