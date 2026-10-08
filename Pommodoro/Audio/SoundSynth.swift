import Foundation

/// Síntesis estéreo continua. Todo el estado está preasignado: render no crea
/// arrays, no usa cerrojos y no hace E/S. Los coeficientes fijos se calculan una vez.
final class SoundSynth {
    struct Params {
        var kind: SoundKind = .none
        var beatHz: Double = 10
        var carrierHz: Double = 200
        var noiseMix: Double = 0.35
    }

    private let sampleRate: Double
    private var params = Params()
    private var leftNoise = Noise(seed: 0x2545_F491_4F6C_DD1D)
    private var rightNoise = Noise(seed: 0x9E37_79B9_7F4A_7C15)
    private var sharedNoise = Noise(seed: 0xD1B5_4A32_D192_ED03)
    private var lowL = 0.0, lowR = 0.0, bed = 0.0
    private var bandL = 0.0, bandR = 0.0, bandLowL = 0.0, bandLowR = 0.0
    private var phaseL = 0.0, phaseR = 0.0, lfoA = 0.0, lfoB = 0.23
    private var eventL = Event(), eventR = Event()
    private var dcInputL = 0.0, dcInputR = 0.0, dcOutputL = 0.0, dcOutputR = 0.0
    private var gain = 0.0, targetGain = 0.0
    private var carrier = 200.0, beat = 10.0, noiseMix = 0.35
    private let gainStep: Double
    private let smooth: Double
    private let lowCoeff: Double, rainCoeff: Double, softRainCoeff: Double, airCoeff: Double
    private let dcPole: Double

    init(sampleRate: Double) {
        precondition(sampleRate >= 8_000 && sampleRate.isFinite)
        self.sampleRate = sampleRate
        gainStep = 1 / (sampleRate * 1.2)
        smooth = 1 - exp(-1 / (sampleRate * 0.025))
        lowCoeff = 1 - exp(-2 * .pi * 350 / sampleRate)
        rainCoeff = 1 - exp(-2 * .pi * 2800 / sampleRate)
        softRainCoeff = 1 - exp(-2 * .pi * 1200 / sampleRate)
        airCoeff = 1 - exp(-2 * .pi * 900 / sampleRate)
        dcPole = exp(-2 * .pi * 8 / sampleRate)
    }

    /// Se llama solo desde el hilo de render, a través del buzón del servicio.
    func update(params: Params) {
        if params.kind != self.params.kind {
            lowL = 0; lowR = 0; bed = 0
            bandL = 0; bandR = 0; bandLowL = 0; bandLowR = 0
            eventL = Event(); eventR = Event()
        }
        self.params = params
        self.params.carrierHz = Self.clamp(params.carrierHz, 80...400, fallback: 200)
        self.params.beatHz = Self.clamp(params.beatHz, 1...45, fallback: 10)
        self.params.noiseMix = Self.clamp(params.noiseMix, 0...0.8, fallback: 0.35)
    }

    func setTargetGain(_ value: Double) { targetGain = Self.clamp(value, 0...1, fallback: 0) }
    var isSilent: Bool { gain <= 0.0001 && targetGain <= 0.0001 }

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        guard frames > 0 else { return }
        for i in 0..<frames {
            gain += min(gainStep, max(-gainStep, targetGain - gain))
            guard gain > 0, params.kind != .none else {
                left[i] = 0; right[i] = 0
                continue
            }
            let (rawL, rawR) = sample()
            // Quita desplazamientos de continua y deja margen para la campana.
            let l = rawL - dcInputL + dcPole * dcOutputL
            let r = rawR - dcInputR + dcPole * dcOutputR
            dcInputL = rawL; dcInputR = rawR; dcOutputL = l; dcOutputR = r
            left[i] = Float((l / (1 + abs(l))) * gain * 0.85)
            right[i] = Float((r / (1 + abs(r))) * gain * 0.85)
        }
    }

    private func sample() -> (Double, Double) {
        switch params.kind {
        case .none: return (0, 0)
        case .white:
            let mid = sharedNoise.white() * 0.10
            return (mid + leftNoise.white() * 0.20, mid + rightNoise.white() * 0.20)
        case .pink:
            let mid = sharedNoise.pink() * 0.38
            return (mid + leftNoise.pink() * 0.55, mid + rightNoise.pink() * 0.55)
        case .brown:
            let mid = sharedNoise.brown() * 0.45
            return (mid + leftNoise.brown() * 0.65, mid + rightNoise.brown() * 0.65)
        case .rain, .softRain:
            advanceLFO(0.083, 0.137)
            let soft = params.kind == .softRain
            let a = soft ? softRainCoeff : rainCoeff
            lowL += a * (leftNoise.white() - lowL)
            lowR += a * (rightNoise.white() - lowR)
            bed += lowCoeff * (sharedNoise.pink() - bed)
            let motion = 0.86 + 0.08 * sin(2 * .pi * lfoA) + 0.06 * sin(2 * .pi * lfoB)
            let texture = soft ? 0.66 : 0.78
            return ((lowL * texture + bed * 0.22) * motion,
                    (lowR * texture + bed * 0.22) * motion)
        case .ocean:
            advanceLFO(0.061, 0.037)
            let swellL = swell(lfoA) * 0.7 + swell(lfoB) * 0.3
            let swellR = swell(lfoA + 0.035) * 0.7 + swell(lfoB + 0.07) * 0.3
            lowL += airCoeff * (leftNoise.white() - lowL)
            lowR += airCoeff * (rightNoise.white() - lowR)
            let deep = sharedNoise.brown() * 0.6
            return ((deep + lowL * 0.55 + leftNoise.pink() * 0.2) * (0.3 + swellL),
                    (deep + lowR * 0.55 + rightNoise.pink() * 0.2) * (0.3 + swellR))
        case .stream:
            advanceLFO(0.19, 0.27)
            // Dos bandas independientes: agua con movimiento lateral, sin un
            // único tono resonante. Coeficientes acotados para mantener estabilidad.
            let fL = 2 * sin(.pi * (950 + 230 * sin(2 * .pi * lfoA)) / sampleRate)
            let fR = 2 * sin(.pi * (1250 + 260 * sin(2 * .pi * lfoB)) / sampleRate)
            let nL = leftNoise.pink(), nR = rightNoise.pink()
            bandLowL += fL * bandL
            bandL += fL * (nL - bandLowL - 0.8 * bandL)
            bandLowR += fR * bandR
            bandR += fR * (nR - bandLowR - 0.8 * bandR)
            return (bandL * 0.65 + nL * 0.3, bandR * 0.65 + nR * 0.3)
        case .wind:
            advanceLFO(0.043, 0.097)
            lowL += airCoeff * (leftNoise.pink() - lowL)
            lowR += airCoeff * (rightNoise.pink() - lowR)
            let gust = 0.55 + swell(lfoA) * 0.65 + swell(lfoB) * 0.25
            let mid = sharedNoise.brown() * 0.25
            return ((lowL + mid) * gust, (lowR + mid) * gust)
        case .fireplace:
            let mid = sharedNoise.brown() * 0.55
            lowL += lowCoeff * (leftNoise.pink() - lowL)
            lowR += lowCoeff * (rightNoise.pink() - lowR)
            let crackL = eventL.crackle(noise: &leftNoise, sampleRate: sampleRate)
            let crackR = eventR.crackle(noise: &rightNoise, sampleRate: sampleRate)
            return (mid + lowL * 0.5 + crackL * 0.3, mid + lowR * 0.5 + crackR * 0.3)
        case .forest:
            advanceLFO(0.029, 0.073)
            lowL += airCoeff * (leftNoise.pink() - lowL)
            lowR += airCoeff * (rightNoise.pink() - lowR)
            let breeze = 0.35 + 0.25 * swell(lfoA)
            let birdL = eventL.bird(noise: &leftNoise, sampleRate: sampleRate)
            let birdR = eventR.bird(noise: &rightNoise, sampleRate: sampleRate)
            return (lowL * breeze + birdL * 0.09 + birdR * 0.025,
                    lowR * breeze + birdR * 0.09 + birdL * 0.025)
        case .fan:
            advanceLFO(0.38, 0.11)
            phaseL += 90 / sampleRate
            if phaseL >= 1 { phaseL -= 1 }
            lowL += airCoeff * (leftNoise.white() - lowL)
            lowR += airCoeff * (rightNoise.white() - lowR)
            let hum = (sin(2 * .pi * phaseL) + sin(4 * .pi * phaseL) * 0.3) * 0.025
            let air = 0.82 + 0.025 * sin(2 * .pi * lfoA)
            return (lowL * air + hum, lowR * air + hum)
        case .binaural:
            carrier += smooth * (params.carrierHz - carrier)
            beat += smooth * (params.beatHz - beat)
            noiseMix += smooth * (params.noiseMix - noiseMix)
            phaseL += carrier / sampleRate; phaseR += (carrier + beat) / sampleRate
            if phaseL >= 1 { phaseL -= 1 }; if phaseR >= 1 { phaseR -= 1 }
            bed += airCoeff * (sharedNoise.pink() - bed)
            let toneGain = 0.25 * (1 - noiseMix * 0.4)
            return (sin(2 * .pi * phaseL) * toneGain + bed * noiseMix,
                    sin(2 * .pi * phaseR) * toneGain + bed * noiseMix)
        }
    }

    private func advanceLFO(_ a: Double, _ b: Double) {
        lfoA += a / sampleRate; lfoB += b / sampleRate
        if lfoA >= 1 { lfoA -= 1 }; if lfoB >= 1 { lfoB -= 1 }
    }
    private func swell(_ phase: Double) -> Double {
        let wave = (sin(2 * .pi * phase) + 1) * 0.5
        return wave * wave
    }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    /// Estado de filtros por canal, sin arrays ni copias con asignación diferida.
    private struct Noise {
        var seed: UInt64
        var p0 = 0.0, p1 = 0.0, p2 = 0.0, p3 = 0.0, p4 = 0.0, p5 = 0.0, p6 = 0.0
        var brownLast = 0.0
        mutating func white() -> Double {
            seed ^= seed >> 12; seed ^= seed << 25; seed ^= seed >> 27
            return Double(Int64(bitPattern: seed &* 2_685_821_657_736_338_717)) / Double(Int64.max)
        }
        mutating func pink() -> Double {
            let w = white()
            p0 = 0.99886 * p0 + w * 0.0555179; p1 = 0.99332 * p1 + w * 0.0750759
            p2 = 0.969 * p2 + w * 0.153852; p3 = 0.8665 * p3 + w * 0.3104856
            p4 = 0.55 * p4 + w * 0.5329522; p5 = -0.7616 * p5 - w * 0.016898
            let out = (p0 + p1 + p2 + p3 + p4 + p5 + p6 + w * 0.5362) * 0.11
            p6 = w * 0.115926
            return out
        }
        mutating func brown() -> Double {
            brownLast = (brownLast + 0.02 * white()) / 1.02
            return brownLast * 3.5
        }
    }

    private struct Event {
        var remaining = 0.0, duration = 0.0, phase = 0.0, pitch = 2600.0
        mutating func crackle(noise: inout Noise, sampleRate: Double) -> Double {
            let white = noise.white()
            if remaining <= 0, white > 1 - 9 / sampleRate {
                duration = 0.008 + abs(noise.white()) * 0.04
                remaining = duration
            }
            guard remaining > 0 else { return 0 }
            let elapsed = duration - remaining
            remaining -= 1 / sampleRate
            let envelope = min(elapsed / 0.002, 1) * max(0, remaining / duration)
            return white * envelope
        }
        mutating func bird(noise: inout Noise, sampleRate: Double) -> Double {
            if remaining <= 0 {
                guard noise.white() > 1 - 0.65 / sampleRate else { return 0 }
                duration = 0.14 + abs(noise.white()) * 0.22
                remaining = duration
                pitch = 2200 + abs(noise.white()) * 1200
                phase = 0
            }
            let t = 1 - remaining / duration
            let envelope = pow(sin(.pi * max(0, min(1, t))), 2)
            phase += (pitch + 450 * sin(2 * .pi * t)) / sampleRate
            if phase >= 1 { phase -= 1 }
            remaining -= 1 / sampleRate
            return sin(2 * .pi * phase) * envelope
        }
    }
}
