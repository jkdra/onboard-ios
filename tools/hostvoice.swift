#!/usr/bin/env swift
//
//  hostvoice.swift — render the On Board Host's chirp "voice" to an audio file.
//
//  Standalone macOS command-line tool (no app target). It reproduces exactly the
//  synthesis the app uses in HostVoice: a soft procedural chirp per character,
//  on every other non-whitespace character, spaced by the same typewriter pacing
//  the welcome cover uses — then writes the whole sequence to an audio file.
//
//  Run it with the Swift toolchain (no build step):
//      swift tools/hostvoice.swift "You're in! Welcome On Board."
//
//  The Host's "voice" is an abstract chirp track (Animal-Crossing style), timed
//  to the text's rhythm — pair it with on-screen captions, not as spoken words.
//

import AVFoundation
import Foundation

// MARK: - Synthesis (mirrors the in-app HostVoice)

let sampleRate = 44_100.0

/// One soft chirp: sine + a quiet 2nd harmonic under a quick attack/decay
/// envelope, pitch nudged by `seed` (the character index).
func chirp(bright: Bool, seed: Int) -> [Float] {
    let duration = 0.06
    let frames = Int(sampleRate * duration)
    let base = bright ? 610.0 : 500.0
    let steps = Double((seed * 7) % 5) - 2          // -2...2, coprime so it varies
    let freq = base * pow(2.0, steps / 24.0)        // ± up to ~a semitone
    let attack = max(frames / 12, 1)                // ~5ms raised-cosine attack
    var out = [Float](repeating: 0, count: frames)
    for i in 0..<frames {
        let t = Double(i) / sampleRate
        let env: Double
        if i < attack {
            env = 0.5 - 0.5 * cos(.pi * Double(i) / Double(attack))
        } else {
            let d = Double(i - attack) / Double(frames - attack)
            env = exp(-4.5 * d)
        }
        let wave = sin(2 * .pi * freq * t) + 0.16 * sin(4 * .pi * freq * t)
        out[i] = Float(wave * env * 0.16)
    }
    return out
}

/// Typewriter cadence in milliseconds after revealing a character.
func pause(after ch: Character) -> Double {
    switch ch {
    case ".", "!", "?": return 300
    case ",", ";", ":": return 175
    case "\n":          return 240
    default:            return 45
    }
}

/// Lay the chirps onto a silent mono buffer at the times they'd play.
func render(_ text: String, bright: Bool) -> [Float] {
    let chars = Array(text)
    guard !chars.isEmpty else { return [] }

    // Total timeline length, then a short tail for the last chirp to ring out.
    var totalMs = 0.0
    for ch in chars { totalMs += pause(after: ch) }
    let tailMs = 120.0
    let totalSamples = Int((totalMs + tailMs) / 1000.0 * sampleRate) + 1
    var buffer = [Float](repeating: 0, count: totalSamples)

    var cursorMs = 0.0
    for (i, ch) in chars.enumerated() {
        let index = i + 1
        if index % 2 == 0 && !ch.isWhitespace {
            let c = chirp(bright: bright, seed: index)
            let offset = Int(cursorMs / 1000.0 * sampleRate)
            for (j, s) in c.enumerated() where offset + j < totalSamples {
                buffer[offset + j] += s          // mix (chirps rarely overlap)
            }
        }
        cursorMs += pause(after: ch)
    }
    // Soft clip guard.
    return buffer.map { max(-1, min(1, $0)) }
}

// MARK: - Write

enum AudioFormat { case m4a, wav }

func write(_ samples: [Float], to url: URL, format: AudioFormat) throws {
    let settings: [String: Any]
    switch format {
    case .m4a:
        settings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 160_000,
        ]
    case .wav:
        settings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }
    let file = try AVAudioFile(forWriting: url, settings: settings)
    guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                     frameCapacity: AVAudioFrameCount(samples.count)) else {
        throw NSError(domain: "hostvoice", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not allocate audio buffer"])
    }
    pcm.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { src in
        pcm.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
    }
    try file.write(from: pcm)
}

// MARK: - CLI

let helpText = """
hostvoice — render the On Board Host's chirp "voice" to an audio file.

USAGE:
  swift tools/hostvoice.swift <text> [options]
  swift tools/hostvoice.swift --text "<text>" [options]

OPTIONS:
  -t, --text <string>      Text to voice (or pass it as the first argument).
  -o, --output <path>      Output file. Default: host-voice.m4a
  -f, --format <m4a|wav>   Audio format. Default: inferred from --output, else m4a.
  -b, --bright             Use the Host's happy (higher-pitched) voice.
  -h, --help               Show this help.

EXAMPLES:
  swift tools/hostvoice.swift "You're in! Welcome On Board."
  swift tools/hostvoice.swift -t "Guess what?" -o guess.m4a --bright
  swift tools/hostvoice.swift "Happy Birthday!" -f wav -o hb.wav

NOTE:
  The Host's voice is an abstract chirp track (Animal-Crossing style), timed to
  the text's rhythm — pair it with on-screen captions, not as spoken words.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n\n" + helpText + "\n").utf8))
    exit(1)
}

var text: String?
var output: String?
var formatArg: String?
var bright = false

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    let arg = args[i]
    switch arg {
    case "-h", "--help":
        print(helpText); exit(0)
    case "-t", "--text":
        i += 1; guard i < args.count else { fail("--text needs a value") }; text = args[i]
    case "-o", "--output":
        i += 1; guard i < args.count else { fail("--output needs a value") }; output = args[i]
    case "-f", "--format":
        i += 1; guard i < args.count else { fail("--format needs a value") }; formatArg = args[i]
    case "-b", "--bright":
        bright = true
    default:
        if arg.hasPrefix("-") { fail("unknown option \(arg)") }
        if text == nil { text = arg } else { fail("unexpected extra argument \(arg)") }
    }
    i += 1
}

guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    fail("no text provided")
}

let outPath = output ?? "host-voice.m4a"
let url = URL(fileURLWithPath: outPath)

let format: AudioFormat
switch (formatArg ?? "").lowercased() {
case "wav": format = .wav
case "m4a", "": format = url.pathExtension.lowercased() == "wav" ? .wav : .m4a
default: fail("--format must be m4a or wav")
}

let samples = render(text, bright: bright)
guard !samples.isEmpty else { fail("nothing to render") }

do {
    try write(samples, to: url, format: format)
    let seconds = Double(samples.count) / sampleRate
    print(String(format: "Wrote %@ (%.1fs, %@%@)",
                 outPath, seconds, format == .m4a ? "AAC m4a" : "WAV", bright ? ", bright" : ""))
} catch {
    fail("could not write \(outPath): \(error.localizedDescription)")
}
