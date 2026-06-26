//
//  BoardJSON.swift
//  On Board
//
//  Shared JSON codecs for Supabase responses (snake_case + ISO-8601).
//

import Foundation

enum BoardJSON {
    nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(parseDate)
        return decoder
    }()

    nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // ISO 8601 with and without fractional seconds — Supabase sends microseconds.
    private nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let isoWhole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static nonisolated func parseDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = isoFractional.date(from: string) { return date }
        if let date = isoWhole.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Invalid date: \(string)"
        )
    }
}
