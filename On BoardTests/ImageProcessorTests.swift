//
//  ImageProcessorTests.swift
//  On BoardTests
//

import Foundation
import Testing
import UIKit
@testable import On_Board

@MainActor
struct ImageProcessorTests {

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func processPostPhotoDownscalesToMaxDimension() {
        let oversized = solidImage(width: 4000, height: 2000)
        guard let data = ImageProcessor.processPostPhoto(oversized) else {
            Issue.record("Expected non-nil JPEG data")
            return
        }
        guard let decoded = UIImage(data: data) else {
            Issue.record("Expected decodable JPEG data")
            return
        }
        #expect(decoded.size.width <= PhotoType.postPhoto.maxDimension)
        #expect(decoded.size.height <= PhotoType.postPhoto.maxDimension)
    }

    @Test func processPostPhotoLeavesSmallImageUnscaled() {
        let small = solidImage(width: 300, height: 200)
        guard let data = ImageProcessor.processPostPhoto(small),
              let decoded = UIImage(data: data) else {
            Issue.record("Expected decodable JPEG data")
            return
        }
        #expect(decoded.size.width == 300)
        #expect(decoded.size.height == 200)
    }
}
