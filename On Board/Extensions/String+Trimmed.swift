//
//  String+Trimmed.swift
//  On Board
//

import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
