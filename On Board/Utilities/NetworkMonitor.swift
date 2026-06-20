//
//  NetworkMonitor.swift
//  On Board
//
//  Tracks device connectivity for the offline gate and onboarding guards.
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var hasReceivedUpdate = false

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.onboard.network-monitor")

    func start() {
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path: path)
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    func recheck() {
        guard let monitor else { return }
        apply(path: monitor.currentPath)
    }

    private func apply(path: NWPath) {
        hasReceivedUpdate = true
        isConnected = path.status == .satisfied
    }
}

enum NetworkErrorClassifier {
    static func isConnectivityFailure(_ error: Error) -> Bool {
        if let error = error as? OnboardingError, error == .networkUnavailable {
            return true
        }
        if let error = error as? AuthError, error == .networkUnavailable {
            return true
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .timedOut,
                 .dnsLookupFailed,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return isConnectivityFailure(URLError(_nsError: nsError))
        }
        return false
    }
}
