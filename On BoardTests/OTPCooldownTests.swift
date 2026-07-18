//
//  OTPCooldownTests.swift
//  On BoardTests
//
//  Pins the destination-aware send window: backing out of the OTP screen must
//  not re-arm sending to the same address, while a *different* address may
//  always be sent to immediately.
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct OTPCooldownTests {

    @Test func freshCooldownAllowsAnyDestination() {
        let cooldown = OTPCooldown()
        #expect(cooldown.canSend(to: "a@school.edu"))
        #expect(cooldown.canResend)
    }

    @Test func sameDestinationBlockedInsideWindow() {
        let cooldown = OTPCooldown()
        cooldown.start(duration: 60, destination: "a@school.edu")
        #expect(!cooldown.canSend(to: "a@school.edu"))
        #expect(!cooldown.canResend)
    }

    @Test func differentDestinationAllowedInsideWindow() {
        let cooldown = OTPCooldown()
        cooldown.start(duration: 60, destination: "a@school.edu")
        #expect(cooldown.canSend(to: "b@school.edu"))
    }

    @Test func resetReopensSameDestination() {
        let cooldown = OTPCooldown()
        cooldown.start(duration: 60, destination: "a@school.edu")
        cooldown.reset()
        #expect(cooldown.canSend(to: "a@school.edu"))
    }

    @Test func startWithoutDestinationStillBlocksResend() {
        // LinkSignInMethodView still uses the destination-less API.
        let cooldown = OTPCooldown()
        cooldown.start(duration: 60)
        #expect(!cooldown.canResend)
        // No recorded destination: an explicit destination is a *different*
        // target, so sending to it is allowed.
        #expect(cooldown.canSend(to: "a@school.edu"))
    }
}
