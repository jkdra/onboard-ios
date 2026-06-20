//
//  SampleProfileID.swift
//  On Board
//
//  Stable UUIDs for sample profiles so ownership checks stay consistent
//  across launches and mock auth sessions.
//

import Foundation

enum SampleProfileID {
    static let maya = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    static let leo = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
    static let aisha = UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!
    static let daniel = UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!
    static let priya = UUID(uuidString: "A0000000-0000-4000-8000-000000000005")!
    static let marcus = UUID(uuidString: "A0000000-0000-4000-8000-000000000006")!
    static let sara = UUID(uuidString: "A0000000-0000-4000-8000-000000000007")!
    static let jordan = UUID(uuidString: "A0000000-0000-4000-8000-000000000008")!
    static let riley = UUID(uuidString: "A0000000-0000-4000-8000-000000000009")!
    static let quinn = UUID(uuidString: "A0000000-0000-4000-8000-00000000000A")!
    static let phone = UUID(uuidString: "A0000000-0000-4000-8000-00000000000B")!
}
