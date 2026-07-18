//
//  PhotoPreviewCache.swift
//  On Board
//
//  Memoizes UIImage decodes for in-memory photo previews. The edit screens
//  render `UIImage(data:)` straight in `body`, which re-decodes a multi-MB
//  JPEG on every body evaluation — i.e. every keystroke while editing a post
//  or profile with a freshly picked photo. Routing the same `Data` through
//  this cache decodes once per blob; NSCache keys by content equality and
//  evicts under memory pressure, so no call site has to manage clearing.
//

import UIKit

enum PhotoPreviewCache {
    private static let cache = NSCache<NSData, UIImage>()

    static func image(for data: Data) -> UIImage? {
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return hit }
        guard let decoded = UIImage(data: data) else { return nil }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
}
