//
//  HostVoice.swift
//  On Board
//
//  The Host's "voice": recorded syllables ("blips") played per letter as the
//  welcome typewriter types, Animal-Crossing "Animalese" style. The sound is
//  DETERMINISTIC and text-driven, and now PHONEME-based: the text is walked as
//  sounds, not letters. Each grapheme maps to a recorded phoneme — vowels to
//  real vowels, consonants to their sound, with digraphs (th/sh/ch/ph) and
//  soft-c/g handled — so words track their real shape ("close to the words
//  without being the words"). Sibilants/fricatives are routed to VOICED chirps
//  (s/z→D, f→P, v→B, th→D, sh/ch→J): Animalese is characterization, not literal
//  speech, and hiss reads as harsh (and worsens under the pitch-up). Vowels play
//  a touch longer/lower for natural consonant-vowel rhythm; melody, a
//  question/statement contour, and a position wobble sit on top. Two recorded
//  sets (neutral + happy) swap on the reveal beat (`bright`). Pitch is in-code
//  varispeed (speed + pitch together).
//
//  Assets: phoneme CAF data sets in Assets.xcassets/HostVoice, named
//  HostVoice<Mood><KEY> (e.g. HostVoiceNeutralAH, HostVoiceHappyD). If they fail
//  to load, the voice falls back to a synthesized chirp so it can't go silent.
//
//  Silent-switch behavior is user-controllable via `SoundEffectsMode`:
//  `.ambient` respects the ringer/silent switch, `.playback` overrides it. Both
//  mix with the user's own audio and never interrupt their music.
//

import AVFoundation
import UIKit

/// How the app's playful sound effects (currently just The Host's voice) behave
/// relative to the ringer/silent switch. Backs an `@AppStorage` picker.
enum SoundEffectsMode: String, CaseIterable, Identifiable {
    case off
    case unlessSilenced
    case always

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:            return "Off"
        case .unlessSilenced: return "On, unless silenced"
        case .always:         return "Always on"
        }
    }

    var isOn: Bool { self != .off }
    /// `.always` overrides the hardware silent switch (`.playback`); `.unlessSilenced`
    /// respects it (`.ambient`).
    var playsWhenSilenced: Bool { self == .always }
}

@MainActor
final class HostVoice {
    static let shared = HostVoice()
    private init() {}

    private let engine = AVAudioEngine()
    /// A small pool of player nodes so rapid blips overlap naturally (like real
    /// speech) instead of cutting each other off — round-robined per letter.
    private var pool: [AVAudioPlayerNode] = []
    private var poolIndex = 0
    private let poolSize = 4
    private let sampleRate = 44100.0
    private var started = false
    private var currentPlaysWhenSilenced = false

    /// Recorded phoneme sets (key → samples), natural pitch. Varispeed at play time.
    private var neutralBlips: [String: [Float]] = [:]
    private var happyBlips: [String: [Float]] = [:]

    /// Per-character phoneme keys for the line currently being spoken, cached so
    /// tokenization (with its digraph lookahead) runs once per line, not per char.
    /// `nil` at an index means "no blip here" — a non-letter, or the 2nd char of
    /// a digraph whose sound already played on the first char.
    private var cachedLine: String?
    private var cachedKeys: [String?] = []

    private let neutralBaseRate = 1.60
    private let happyBaseRate = 1.72

    // MARK: - Phoneme tables

    /// Every phoneme key the mapping can produce (the no-hiss subset). Order
    /// gives each a stable index for the melody.
    static let phonemeOrder = [
        "AH", "EH", "IH", "EE", "OH", "OO", "UH",   // vowels
        "M", "N", "L", "R", "W", "Y", "H",          // soft consonants
        "B", "P", "D", "T", "G", "K",               // hard consonants
        "J",                                        // voiced fricative kept
        "S",                                        // softened real S (dark, short, low-pitched)
    ]
    private static let phonemeIndex: [String: Int] =
        Dictionary(uniqueKeysWithValues: phonemeOrder.enumerated().map { ($1, $0) })
    private static let vowels: Set<String> = ["AH", "EH", "IH", "EE", "OH", "OO", "UH"]

    /// Vowel-forward mix: consonants sit UNDER the vowels so the punchy plosives
    /// (K/T/P) punctuate rather than punch, and the softened S stays subordinate.
    private static func gain(for key: String) -> Float {
        if vowels.contains(key) { return 1.0 }
        switch key {
        case "M", "N", "L", "R", "W", "Y", "H": return 0.85
        case "P", "T", "K":                     return 0.55   // punchy voiceless plosives, pulled back most
        case "B", "D", "G":                     return 0.70
        case "S":                               return 0.40   // softened S, well under everything
        default:                                return 0.70   // J
        }
    }
    /// The softened S is pitched far less than the rest — sibilant energy read as
    /// "s" at natural frequency; the chipmunk lift would turn it back into hiss.
    private static let sibilantRate = 1.30

    /// Two-letter graphemes → phoneme (checked before single letters). Fricatives
    /// route to voiced chirps: th→D, sh/ch→J, ph→P.
    private static let digraph: [String: String] = [
        "th": "D", "sh": "J", "ch": "J", "ph": "P", "wh": "W", "ck": "K", "ng": "N",
        "ee": "EE", "oo": "OO", "ea": "EE", "oa": "OH", "ou": "OO", "ow": "OO",
        "ai": "EH", "ay": "EH",
    ]
    /// Single letter → phoneme. `s` (and soft `c`) → the softened `S`; the other
    /// fricatives stay voiced (z→D, f→P, v→B) — S is the only one tame enough to
    /// bring back.
    private static let single: [Character: String] = [
        "a": "AH", "e": "EH", "i": "IH", "o": "OH", "u": "UH", "y": "Y",
        "b": "B", "c": "K", "d": "D", "f": "P", "g": "G", "h": "H", "j": "J",
        "k": "K", "l": "L", "m": "M", "n": "N", "p": "P", "q": "K", "r": "R",
        "s": "S", "t": "T", "v": "B", "w": "W", "x": "K", "z": "D",
    ]

    // MARK: - Lifecycle

    /// Warm the engine, load the phoneme sets, and pick the audio-session
    /// category. `.playback` ignores the silent switch; `.ambient` respects it.
    /// Both mix with other audio. Safe to call repeatedly — it only reconfigures
    /// when the silent-switch preference changes.
    func prepare(playsWhenSilenced: Bool) {
        if !started || currentPlaysWhenSilenced != playsWhenSilenced {
            currentPlaysWhenSilenced = playsWhenSilenced
            // AVAudioSession activation is synchronous and can hitch the UI on the
            // main thread, so configure it off-main (fire-and-forget). The engine
            // below starts right away; the session goes active a beat later, which
            // is fine — prepare() is a warm-up call made well before the first blip.
            let category: AVAudioSession.Category = playsWhenSilenced ? .playback : .ambient
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(category, options: [.mixWithOthers])
                try? session.setActive(true)
            }
        }
        guard !started else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        if neutralBlips.isEmpty { neutralBlips = loadBlipSet(mood: "Neutral") }
        if happyBlips.isEmpty { happyBlips = loadBlipSet(mood: "Happy") }

        pool.removeAll()
        for _ in 0..<poolSize {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            pool.append(node)
        }
        do {
            try engine.start()
            pool.forEach { $0.play() }
            started = true
        } catch {
            started = false
        }
    }

    /// Tear down and release the audio session when the welcome cover leaves.
    func stop() {
        guard started else { return }
        pool.forEach { $0.stop() }
        engine.stop()
        // Deactivate off-main for the same reason as activation (avoids the
        // main-thread-hang warning from a synchronous AVAudioSession call).
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        started = false
    }

    // MARK: - Speaking

    /// Voice one character of `line` at `index` (0-based). A blip plays only when
    /// this character starts a phoneme; non-letters and the trailing char of a
    /// digraph are silent (they're the pauses/tails). `bright` selects the happy
    /// set + a slightly higher base pitch for the reveal beat.
    func speak(_ character: Character, at index: Int, in line: String, bright: Bool) {
        guard started, engine.isRunning else { return }
        let set = bright ? happyBlips : neutralBlips
        guard !set.isEmpty else { chirpFallback(bright: bright, seed: index); return }

        if cachedLine != line {
            cachedLine = line
            cachedKeys = phonemeKeys(for: line)
        }
        guard index >= 0, index < cachedKeys.count,
              let key = cachedKeys[index], let blip = set[key],
              let buffer = resample(blip,
                                    rate: rate(forKey: key, index: index, in: line, bright: bright),
                                    gain: Self.gain(for: key))
        else { return }

        let node = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Walk the line into per-character phoneme keys (digraphs consume two chars,
    /// marking the second `nil`; soft-c/g resolved; sibilants routed voiced).
    private func phonemeKeys(for line: String) -> [String?] {
        let cs = Array(line.lowercased())
        var keys = [String?](repeating: nil, count: cs.count)
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if !c.isLetter { i += 1; continue }
            if (c == "c" || c == "g"), i + 1 < cs.count, "eiy".contains(cs[i + 1]) {
                keys[i] = (c == "c") ? "S" : "J"   // soft c → S, soft g → J
                i += 1
            } else if i + 1 < cs.count, let d = Self.digraph[String([c, cs[i + 1]])] {
                keys[i] = d
                i += 2
            } else {
                keys[i] = Self.single[c] ?? "UH"
                i += 1
            }
        }
        return keys
    }

    /// The pitch rate for one phoneme: base (mood) × the sum of a per-phoneme
    /// melody, a vowel dip (vowels lower/longer), a deterministic position
    /// wobble, and the sentence contour — all in semitones.
    private func rate(forKey key: String, index: Int, in line: String, bright: Bool) -> Double {
        // The softened S ignores melody/mood/contour and rides a low fixed rate
        // (a tiny wobble for life) — the whole point is it barely pitches up.
        if key == "S" {
            let wobble = (Double((index * 7) % 5) - 2.0) * 0.10
            return Self.sibilantRate * pow(2.0, wobble / 12.0)
        }
        let base = bright ? happyBaseRate : neutralBaseRate
        let pIdx = Self.phonemeIndex[key] ?? 0
        let melody = (Double((pIdx * 4) % 7) - 3.0) * 0.4
        let wobble = (Double((index * 7) % 5) - 2.0) * 0.12
        let vowelLow = Self.vowels.contains(key) ? -1.2 : 0.0
        let contour = contourSemitone(at: index, in: line)
        return base * pow(2.0, (melody + wobble + vowelLow + contour) / 12.0)
    }

    /// Looks a few characters ahead for a sentence terminator and lifts the pitch
    /// toward a `?` (or settles it before `.`/`!`), strongest closest to the mark.
    private func contourSemitone(at index: Int, in line: String) -> Double {
        let chars = Array(line)
        let ramp = 5
        for d in 1...ramp {
            let j = index + d
            guard j < chars.count else { break }
            switch chars[j] {
            case "?": return 2.2 * Double(ramp - d + 1) / Double(ramp)
            case ".", "!": return -1.2 * Double(ramp - d + 1) / Double(ramp)
            default: continue
            }
        }
        return 0
    }

    // MARK: - Sample loading & varispeed

    private func loadBlipSet(mood: String) -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        for key in Self.phonemeOrder {
            guard let asset = NSDataAsset(name: "HostVoice\(mood)\(key)") else { continue }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("HostVoice\(mood)\(key)-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard (try? asset.data.write(to: tmp)) != nil,
                  let file = try? AVAudioFile(forReading: tmp),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil,
                  let data = buffer.floatChannelData
            else { continue }
            result[key] = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }
        return result
    }

    /// Linear-interpolation varispeed: `rate` > 1 shortens and raises pitch
    /// together (the chipmunk effect), the way Animalese speeds recorded speech.
    private func resample(_ x: [Float], rate: Double, gain: Float) -> AVAudioPCMBuffer? {
        guard x.count > 1, rate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return nil }
        let n = max(1, Int(Double(x.count) / rate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(n)
        let out = buffer.floatChannelData![0]
        for k in 0..<n {
            let p = Double(k) * rate
            let a = Int(p)
            let frac = Float(p - Double(a))
            let sample = a + 1 < x.count ? x[a] * (1 - frac) + x[a + 1] * frac : x[a]
            out[k] = sample * gain
        }
        return buffer
    }

    // MARK: - Synth fallback (used only if the recorded phonemes fail to load)

    private func chirpFallback(bright: Bool, seed: Int) {
        guard started, engine.isRunning, !pool.isEmpty else { return }
        let base = bright ? 610.0 : 500.0
        let steps = Double((seed * 7) % 5) - 2
        let freq = base * pow(2.0, steps / 24.0)
        guard let buffer = makeChirp(frequency: freq) else { return }
        let node = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func makeChirp(frequency: Double) -> AVAudioPCMBuffer? {
        let duration = 0.06
        let frameCount = Int(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        let attack = max(frameCount / 12, 1)
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let env: Double
            if i < attack {
                env = 0.5 - 0.5 * cos(.pi * Double(i) / Double(attack))
            } else {
                let d = Double(i - attack) / Double(frameCount - attack)
                env = exp(-4.5 * d)
            }
            let wave = sin(2 * .pi * frequency * t) + 0.16 * sin(4 * .pi * frequency * t)
            samples[i] = Float(wave * env * 0.16)
        }
        return buffer
    }
}
