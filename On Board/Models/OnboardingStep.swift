//
//  OnboardingStep.swift
//  On Board
//

import Foundation

enum OnboardingStep: String, Codable, Sendable, CaseIterable {
    case username
    case profile
    case schoolVerify = "school_verify"
    case waitlist
    case complete
}
