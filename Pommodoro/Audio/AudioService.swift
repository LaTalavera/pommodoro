import AVFoundation
import Foundation
import os

enum ChimeKind {
    /// Fin del bloque de trabajo: dos notas descendentes, invita a soltar.
    case breakStart
    /// Fin del descanso: dos notas ascendentes, invita a arrancar.
    case workStart

    var notes: [Double] {
        switch self {
        case .breakStart: [783.99, 523.25]
        case .workStart: [523.25, 783.99]
        }
    }
}

/// Todo lo que hace falta para saber qué debe sonar. Es un valor, así que la
/// hoja de sonido puede hacer preview de una combinación sin tocar los ajustes.
struct SoundConfig: Equatable {
    var kind: SoundKind = .none
    var volume: Double = 0.55
    var beatHz: Double = 10
    var carrierHz: Double = 200
    var noiseMix: Double = 0.35
    var mixWithOthers: Bool = true

    /// Los tonos binaurales se presentan sin mezclar audio de otras apps.
    var allowsMixing: Bool { mixWithOthers && kind != .binaural }
}

/// Motor de audio único de la app: sintetiza el paisaje sonoro de fondo y las
/// campanas de transición. No hay recursos de audio en el bundle.
@MainActor
final class AudioService {
    static let shared = AudioService()

    private let sampleRate: Double = 44_100
    private let engine = AVAudioEngine()
    private let ambientMixer = AVAudioMixerNode()
    private let chimePlayer = AVAudioPlayerNode()
    private let synth: SoundSynth
    private var sourceNode: AVAudioSourceNode?
    private var format: AVAudioFormat!

    /// Los parámetros viajan al hilo de audio por este buzón; el hilo de render
    /// solo lo consulta con `trylock`, así nunca se queda esperando.
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)

    private var currentConfig = SoundConfig()
    private var isSessionActive = false
    private var activeCategoryAllowsMixing: Bool?
    private var stopWorkItem: DispatchWorkItem?
    private var swapWorkItem: DispatchWorkItem?
    private var chimeBusyUntil = Date.distantPast

    /// Un pelo más que la rampa del sintetizador (1,2 s), para que el cambio de
    /// timbre ocurra con el volumen ya a cero.
    private static let fadeDuration: TimeInterval = 1.35

    private init() {
        lock.initialize(to: os_unfair_lock())
        synth = SoundSynth(sampleRate: sampleRate)
        buildGraph()
        observeInterruptions()
    }

    // MARK: - Grafo

    private func buildGraph() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let node = AVAudioSourceNode(format: format) { [synth, lock] _, _, frameCount, audioBufferList in
            if os_unfair_lock_trylock(lock) {
                // `pendingParams`/`pendingGain` solo se tocan bajo este cerrojo.
                if let p = AudioService.mailbox.params {
                    synth.update(params: p)
                    AudioService.mailbox.params = nil
                }
                if let g = AudioService.mailbox.gain {
                    synth.setTargetGain(g)
                    AudioService.mailbox.gain = nil
                }
                os_unfair_lock_unlock(lock)
            }

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = abl[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            synth.render(frames: Int(frameCount), left: l, right: r)
            return noErr
        }
        sourceNode = node

        engine.attach(node)
        engine.attach(ambientMixer)
        engine.attach(chimePlayer)
        engine.connect(node, to: ambientMixer, format: format)
        engine.connect(ambientMixer, to: engine.mainMixerNode, format: format)
        engine.connect(chimePlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
    }

    /// Buzón compartido con el hilo de render. Es estático para que el bloque
    /// de render no tenga que capturar `self` (aislado a `@MainActor`).
    nonisolated(unsafe) private static var mailbox = (params: SoundSynth.Params?.none, gain: Double?.none)

    // MARK: - API pública

    /// Pone a sonar la configuración indicada.
    ///
    /// Cambiar de paisaje sonoro no corta en seco: primero se va el volumen y
    /// solo después se cambia el generador, así el salto de timbre ocurre en
    /// silencio. Los ajustes continuos (volumen, batido) se aplican al vuelo.
    func apply(_ config: SoundConfig) {
        let kindChanged = config.kind != currentConfig.kind
        let wasAudible = !currentConfig.kind.isSilent
        currentConfig = config

        // Durante una transición conservamos la rampa y aplicamos al terminar
        // la selección más reciente, incluidos los cambios de volumen.
        if swapWorkItem != nil { return }
        updateSessionCategory(for: config)

        guard kindChanged, wasAudible else {
            post(params: Self.params(from: config), gain: config.kind.isSilent ? 0 : config.volume)
            settleEngine(for: config)
            return
        }

        post(params: nil, gain: 0)
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.swapWorkItem = nil
                let config = self.currentConfig
                self.updateSessionCategory(for: config)
                self.post(params: Self.params(from: config), gain: config.kind.isSilent ? 0 : config.volume)
                self.settleEngine(for: config)
            }
        }
        swapWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration, execute: item)
        if !config.kind.isSilent { startEngineIfNeeded() }
    }

    /// Baja el fondo antes de la campana de fin de fase, para que el aviso no
    /// llegue encima de un paisaje sonoro a todo volumen.
    func fadeOutForPhaseChange() {
        guard !currentConfig.kind.isSilent else { return }
        swapWorkItem?.cancel()
        swapWorkItem = nil
        post(params: nil, gain: 0)
    }

    private func settleEngine(for config: SoundConfig) {
        if config.kind.isSilent {
            scheduleStopIfIdle(after: Self.fadeDuration + 0.5)
        } else {
            startEngineIfNeeded()
        }
    }

    private static func params(from config: SoundConfig) -> SoundSynth.Params {
        SoundSynth.Params(
            kind: config.kind,
            beatHz: config.beatHz,
            carrierHz: config.carrierHz,
            noiseMix: config.noiseMix
        )
    }

    func playChime(_ kind: ChimeKind) {
        startEngineIfNeeded()
        guard let buffer = makeChimeBuffer(kind) else { return }
        chimeBusyUntil = Date().addingTimeInterval(buffer.duration)
        chimePlayer.scheduleBuffer(buffer, at: nil, options: [])
        if !chimePlayer.isPlaying { chimePlayer.play() }
        scheduleStopIfIdle(after: buffer.duration + 0.5)
    }

    /// Llamar al volver a primer plano: reanuda el motor si el sistema lo paró.
    func resumeIfNeeded() {
        guard !currentConfig.kind.isSilent else { return }
        startEngineIfNeeded()
    }

    // MARK: - Interno

    private func post(params: SoundSynth.Params?, gain: Double?) {
        os_unfair_lock_lock(lock)
        if let params { AudioService.mailbox.params = params }
        if let gain { AudioService.mailbox.gain = gain }
        os_unfair_lock_unlock(lock)
    }

    private func startEngineIfNeeded() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        activateSession()
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            // Sin audio la app sigue siendo perfectamente usable.
            print("AudioService: no se pudo arrancar el motor — \(error.localizedDescription)")
        }
    }

    private func scheduleStopIfIdle(after seconds: TimeInterval = 2.0) {
        stopWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.currentConfig.kind.isSilent, Date() >= self.chimeBusyUntil else { return }
                self.chimePlayer.stop()
                self.engine.stop()
                self.deactivateSession()
            }
        }
        stopWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Reconfigura la sesión cuando cambia si debemos convivir con otro audio.
    private func updateSessionCategory(for config: SoundConfig) {
        let allowsMixing = config.allowsMixing
        guard activeCategoryAllowsMixing != allowsMixing else { return }
        activeCategoryAllowsMixing = allowsMixing
        guard isSessionActive else { return }
        applyCategory(allowsMixing: allowsMixing)
    }

    // macOS no tiene `AVAudioSession`: el motor de audio suena sin configurar
    // categorías y el sistema ya mezcla con el resto de apps.
    #if os(iOS)
    private func applyCategory(allowsMixing: Bool) {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: allowsMixing ? [.mixWithOthers] : []
            )
        } catch {
            print("AudioService: categoría de audio — \(error.localizedDescription)")
        }
    }

    private func activateSession() {
        guard !isSessionActive else { return }
        do {
            applyCategory(allowsMixing: activeCategoryAllowsMixing ?? currentConfig.allowsMixing)
            try AVAudioSession.sharedInstance().setActive(true)
            isSessionActive = true
        } catch {
            print("AudioService: sesión de audio — \(error.localizedDescription)")
        }
    }

    private func deactivateSession() {
        guard isSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw)
                else { return }
                switch type {
                case .began:
                    self.isSessionActive = false
                    self.engine.pause()
                case .ended:
                    self.resumeIfNeeded()
                @unknown default:
                    break
                }
            }
        }
    }

    #else
    private func applyCategory(allowsMixing: Bool) {}

    private func activateSession() {
        isSessionActive = true
    }

    private func deactivateSession() {
        isSessionActive = false
    }

    private func observeInterruptions() {}
    #endif

    // MARK: - Síntesis de la campana

    /// Campana aditiva: parciales inarmónicos con caídas exponenciales
    /// distintas, que es lo que da el timbre metálico y suave.
    private func makeChimeBuffer(_ kind: ChimeKind) -> AVAudioPCMBuffer? {
        let duration = 3.0
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let channels = buffer.floatChannelData else { return nil }

        let ratios: [Double] = [1.0, 2.0, 2.76, 5.4]
        let amps: [Double] = [1.0, 0.5, 0.26, 0.12]
        let decays: [Double] = [2.2, 1.5, 0.9, 0.5]

        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            var value = 0.0
            for (index, note) in kind.notes.enumerated() {
                let onset = Double(index) * 0.3
                guard t >= onset else { continue }
                let local = t - onset
                for p in 0..<ratios.count {
                    let env = exp(-local / decays[p])
                    value += sin(2 * .pi * note * ratios[p] * local) * amps[p] * env
                }
            }
            // Ataque corto para que no chasquee al empezar.
            let attack = min(t / 0.006, 1)
            let sample = Float(value * 0.075 * attack)
            channels[0][i] = sample
            channels[1][i] = sample
        }
        return buffer
    }
}

private extension AVAudioPCMBuffer {
    var duration: TimeInterval {
        TimeInterval(frameLength) / format.sampleRate
    }
}
