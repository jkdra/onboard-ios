//
//  Tag.swift
//  On Board
//

import Foundation

struct Tag: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let postCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case postCount = "post_count"
    }
}
