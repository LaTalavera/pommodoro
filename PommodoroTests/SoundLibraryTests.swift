import Foundation
import Testing
@testable import Pommodoro

@Suite("Biblioteca de sonidos")
struct SoundLibraryTests {
    @MainActor @Test func launchIgnoresSavedSoundsButRetainsPreferences() {
        let name = "SoundTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("rain", forKey: "soundID")
        defaults.set("ocean", forKey: "breakSoundID")
        defaults.set(0.27, forKey: "soundVolume")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.sound == .none)
        #expect(settings.breakSound == .none)
        #expect(settings.soundVolume == 0.27)
        settings.sound = .forest
        settings.breakSound = .fan
        #expect(settings.sound == .forest)
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.sound == .none)
        #expect(reopened.breakSound == .none)
        #expect(reopened.soundVolume == 0.27)
    }

    @Test func categoriesCoverEveryAudibleSoundOnce() {
        let sounds = SoundCategory.allCases.flatMap(\.sounds)
        #expect(Set(sounds) == Set(SoundKind.allCases.filter { !$0.isSilent }))
        #expect(sounds.count == Set(sounds).count)
    }

    private func render(_ synth: SoundSynth, frames: Int) -> ([Float], [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                synth.render(frames: frames, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        return (left, right)
    }

    @Test(arguments: SoundKind.allCases.filter { !$0.isSilent }, [44_100.0, 48_000.0])
    func stereoOutputIsFiniteBoundedAndFadesToSilence(kind: SoundKind, rate: Double) {
        let synth = SoundSynth(sampleRate: rate)
        synth.update(params: .init(kind: kind))
        synth.setTargetGain(1)
        let (left, right) = render(synth, frames: Int(rate * 3))
        #expect(abs(left[0]) < 0.0001)
        for channel in [left, right] {
            #expect(channel.allSatisfy { $0.isFinite && abs($0) < 0.85 })
            let tail = channel.suffix(Int(rate))
            let energy = tail.reduce(0.0) { $0 + Double($1 * $1) } / rate
            #expect(energy > 0.000001)
            #expect(abs(tail.reduce(0.0) { $0 + Double($1) } / rate) < 0.02)
        }
        #expect(left != right)
        synth.setTargetGain(0)
        let faded = render(synth, frames: Int(rate * 1.3))
        #expect(synth.isSilent)
        #expect(faded.0.suffix(100).allSatisfy { $0 == 0 })
        #expect(faded.1.suffix(100).allSatisfy { $0 == 0 })
    }

    @Test func binauralChannelsKeepTheirRequestedFrequencies() {
        let synth = SoundSynth(sampleRate: 48_000)
        synth.update(params: .init(kind: .binaural, beatHz: 16, carrierHz: 240, noiseMix: 0))
        synth.setTargetGain(0.55)
        _ = render(synth, frames: 96_000)
        let channels = render(synth, frames: 48_000)
        func crossings(_ samples: [Float]) -> Int {
            zip(samples, samples.dropFirst()).filter { $0.0 <= 0 && $0.1 > 0 }.count
        }
        #expect(abs(crossings(channels.0) - 240) <= 1)
        #expect(abs(crossings(channels.1) - 256) <= 1)
    }

    @Test func silenceAndInvalidParametersAreSafe() {
        let synth = SoundSynth(sampleRate: 44_100)
        synth.setTargetGain(1)
        #expect(render(synth, frames: 1000).0.allSatisfy { $0 == 0 })
        synth.update(params: .init(kind: .binaural, beatHz: .nan, carrierHz: .infinity, noiseMix: -.infinity))
        #expect(render(synth, frames: 1000).0.allSatisfy { $0.isFinite })
        synth.setTargetGain(.nan)
        _ = render(synth, frames: 60_000)
        #expect(synth.isSilent)
    }
}
