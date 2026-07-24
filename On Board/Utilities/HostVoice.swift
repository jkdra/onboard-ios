//
//  HostVoice.swift
//  On Board
//
//  The Host's "voice": a soft, Omori-style synth chirp played per character as
//  the welcome typewriter types (paired with the mouth-flap sprite and the
//  haptic beat). The chirp is SYNTHESIZED procedurally — a short sine burst with
//  a quick attack/decay envelope, pitch nudged per character — so there's no
//  audio asset to ship or license, and pitch variation is free.
//
//  Silent-switch behavior is user-controllable via `SoundEffectsMode`:
//  `.ambient` respects the ringer/silent switch, `.playback` overrides it. Both
//  mix with the user's own audio and never interrupt their music.
//

import AVFoundation

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
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44100.0
    private var started = false
    private var currentPlaysWhenSilenced = false

    /// Warm the engine and pick the audio-session category. `.playback` ignores
    /// the silent switch; `.ambient` respects it. Both mix with other audio so
    /// the chirp never stops the user's music. Safe to call repeatedly — it only
    /// reconfigures when the silent-switch preference actually changes.
    func prepare(playsWhenSilenced: Bool) {
        let session = AVAudioSession.sharedInstance()
        if !started || currentPlaysWhenSilenced != playsWhenSilenced {
            let category: AVAudioSession.Category = playsWhenSilenced ? .playback : .ambient
            try? session.setCategory(category, options: [.mixWithOthers])
            try? session.setActive(true)
            currentPlaysWhenSilenced = playsWhenSilenced
        }
        guard !started else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            started = false
        }
    }

    /// Play one soft chirp. `bright` raises the base pitch a touch (the happier
    /// reveal beat); `seed` (the character index) gives repeatable variation so
    /// the voice feels alive without a random-number dependency.
    func chirp(bright: Bool, seed: Int) {
        guard started, engine.isRunning else { return }
        let base = bright ? 610.0 : 500.0
        // `seed` is the (even) character index, so a coprime multiplier is needed
        // to actually cycle the pitch — `seed * 5 % 5` is always 0.
        let steps = Double((seed * 7) % 5) - 2          // -2...2 semitone-ish
        let freq = base * pow(2.0, steps / 24.0)        // ± up to ~a semitone
        guard let buffer = makeChirp(frequency: freq) else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Tear down and release the audio session when the welcome cover leaves.
    func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        started = false
    }

    private func makeChirp(frequency: Double) -> AVAudioPCMBuffer? {
        let duration = 0.06
        let frameCount = Int(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        let attack = max(frameCount / 12, 1)            // ~5ms raised-cosine attack
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Envelope: soft attack, then exponential decay to silence.
            let env: Double
            if i < attack {
                env = 0.5 - 0.5 * cos(.pi * Double(i) / Double(attack))
            } else {
                let d = Double(i - attack) / Double(frameCount - attack)
                env = exp(-4.5 * d)
            }
            // Sine plus a quiet 2nd harmonic for a rounded, warm timbre.
            let wave = sin(2 * .pi * frequency * t) + 0.16 * sin(4 * .pi * frequency * t)
            samples[i] = Float(wave * env * 0.16)
        }
        return buffer
    }
}
