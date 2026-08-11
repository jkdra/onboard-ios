//
//  NetworkErrorClassifierTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct NetworkErrorClassifierTests {
    @Test func zeroByteResourceIsConnectivityFailure() {
        #expect(NetworkErrorClassifier.isConnectivityFailure(URLError(.zeroByteResource)))
    }

    @Test func notConnectedToInternetIsConnectivityFailure() {
        #expect(NetworkErrorClassifier.isConnectivityFailure(URLError(.notConnectedToInternet)))
    }

    @Test func badServerResponseIsNotConnectivityFailure() {
        #expect(!NetworkErrorClassifier.isConnectivityFailure(URLError(.badServerResponse)))
    }
}
