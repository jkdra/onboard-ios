//
//  ProfileIndexTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct ProfileIndexTests {
    @Test func looksUpByHandleCaseInsensitively() {
        let index = ProfileIndex(profiles: Profile.samples)
        #expect(index.profile(handle: "MAYA.C")?.id == SampleProfileID.maya)
        #expect(index.profile(id: SampleProfileID.leo)?.handle == "leokp")
    }
}
