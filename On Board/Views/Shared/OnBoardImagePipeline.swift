//
//  OnBoardImagePipeline.swift
//  On Board
//
//  Configures the shared Nuke pipeline with an on-disk cache for decoded
//  images, so thumbnails survive relaunches and scroll-back without re-decode.
//  Per-request downsampling (see BoardAsyncImage / AvatarView) is what keeps
//  memory bounded — a 4032×3024 camera photo would otherwise decode to ~48MB
//  to fill a ~190pt card.
//

import CoreGraphics
import Foundation
import Nuke

enum OnBoardImagePipeline {
    /// Call once at app launch, before any image loads.
    static func configure() {
        // Disk: 50MB — one board week of image posts fits comfortably; old entries
        // are evicted LRU so the cache never silently balloons.
        let disk = try? DataCache(name: "org.onboardapp.images")
        disk?.sizeLimit = 50 * 1024 * 1024

        // Memory: 30MB — downsampled thumbnails are small; this holds ~15-20 cards.
        let memory = ImageCache()
        memory.costLimit = 30 * 1024 * 1024

        ImagePipeline.shared = ImagePipeline {
            $0.dataCache = disk
            // .automatic stores the *processed* (downsampled) image for requests
            // with processors, and original data for those without.
            $0.dataCachePolicy = .automatic
            $0.imageCache = memory
        }
    }

    /// Downsampled request for a thumbnail/avatar shown at `width` points.
    /// Resize accounts for screen scale internally, so pass the point width.
    static func request(url: URL, width: CGFloat) -> ImageRequest {
        ImageRequest(url: url, processors: [ImageProcessors.Resize(width: width)])
    }
}
