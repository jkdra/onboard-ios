//
//  HostVoiceAssetsTests.swift
//  On BoardTests
//
//  Guards that The Host's recorded voice blips actually bundle and decode.
//  If a data set is renamed/dropped, HostVoice silently falls back to the synth
//  chirp — this catches that at build time instead of on-device.
//

import Foundation
import AVFoundation
import UIKit
import Testing
@testable import On_Board

@MainActor
struct HostVoiceAssetsTests {

    /// Every phoneme the mapping can produce resolves via NSDataAsset, in both
    /// moods — so nothing silently falls through to the synth chirp.
    @Test func allPhonemesResolve() {
        for key in HostVoice.phonemeOrder {
            #expect(NSDataAsset(name: "HostVoiceNeutral\(key)") != nil, "missing HostVoiceNeutral\(key)")
            #expect(NSDataAsset(name: "HostVoiceHappy\(key)") != nil, "missing HostVoiceHappy\(key)")
        }
    }

    /// A blip decodes to real, non-silent PCM audio at the expected format.
    @Test func blipDecodesToAudio() throws {
        let asset = try #require(NSDataAsset(name: "HostVoiceNeutralAH"))
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hv-test-\(UUID().uuidString).caf")
        try asset.data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = try AVAudioFile(forReading: tmp)
        #expect(file.length > 0, "blip has no frames")

        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.1, "blip is silent (peak \(peak))")
    }
}
