import Foundation
import Observation

/// Preferencias del usuario, persistidas en `UserDefaults`.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var workMinutes: Int { didSet { save(workMinutes, .workMinutes) } }
    var shortBreakMinutes: Int { didSet { save(shortBreakMinutes, .shortBreakMinutes) } }
    var longBreakMinutes: Int { didSet { save(longBreakMinutes, .longBreakMinutes) } }
    var sessionsBeforeLongBreak: Int { didSet { save(sessionsBeforeLongBreak, .sessionsBeforeLongBreak) } }
    /// Bloques de concentración que se proponen para un día. La técnica está en
    /// parar, no en seguir: es un objetivo, no un tope duro.
    var dailyGoal: Int { didSet { save(dailyGoal, .dailyGoal) } }
    var dailyGoalModeID: String { didSet { save(dailyGoalModeID, .dailyGoalModeID) } }
    var dailyGoalMinutes: Int { didSet { save(dailyGoalMinutes, .dailyGoalMinutes) } }
    var lastGoalCelebrationDay: Date? {
        didSet { defaults.set(lastGoalCelebrationDay, forKey: Key.lastGoalCelebrationDay.rawValue) }
    }

    var dailyGoalMode: DailyGoalMode {
        get { DailyGoalMode(rawValue: dailyGoalModeID) ?? .blocks }
        set { dailyGoalModeID = newValue.rawValue }
    }
    /// Recordar que actives tu Concentración si empiezas un bloque sin una
    /// puesta. iOS no deja que ninguna app la active por ti.
    var suggestFocusMode: Bool { didSet { save(suggestFocusMode, .suggestFocusMode) } }

    var autoStartBreaks: Bool { didSet { save(autoStartBreaks, .autoStartBreaks) } }
    var autoStartWork: Bool { didSet { save(autoStartWork, .autoStartWork) } }
    var keepScreenAwake: Bool { didSet { save(keepScreenAwake, .keepScreenAwake) } }
    var hapticsEnabled: Bool { didSet { save(hapticsEnabled, .hapticsEnabled) } }
    var chimeEnabled: Bool { didSet { save(chimeEnabled, .chimeEnabled) } }

    /// La selección solo vive durante esta apertura: nunca arranca audio desde disco.
    var soundID: String
    /// Sonido de los descansos. Por defecto sigue al de concentración.
    var breakFollowsWorkSound: Bool { didSet { save(breakFollowsWorkSound, .breakFollowsWorkSound) } }
    var breakSoundID: String
    /// Si el sonido de fondo convive con la música que ya suene en el móvil.
    var mixWithOtherAudio: Bool { didSet { save(mixWithOtherAudio, .mixWithOtherAudio) } }
    var immersionModeID: String { didSet { save(immersionModeID, .immersionModeID) } }
    var soundVolume: Double { didSet { save(soundVolume, .soundVolume) } }
    var binauralBeatHz: Double { didSet { save(binauralBeatHz, .binauralBeatHz) } }
    var binauralCarrierHz: Double { didSet { save(binauralCarrierHz, .binauralCarrierHz) } }
    /// Mezcla de ruido rosa bajo el tono binaural, para que no resulte áspero.
    var binauralNoiseMix: Double { didSet { save(binauralNoiseMix, .binauralNoiseMix) } }

    private enum Key: String {
        case workMinutes, shortBreakMinutes, longBreakMinutes, sessionsBeforeLongBreak
        case autoStartBreaks, autoStartWork, keepScreenAwake, hapticsEnabled, chimeEnabled
        case dailyGoal, suggestFocusMode
        case dailyGoalModeID, dailyGoalMinutes, lastGoalCelebrationDay
        case soundID, soundVolume, binauralBeatHz, binauralCarrierHz, binauralNoiseMix
        case breakFollowsWorkSound, breakSoundID, mixWithOtherAudio, immersionModeID
    }

    private let defaults: UserDefaults

    /// El almacén es inyectable para que los tests puedan trabajar sobre un
    /// dominio aislado en vez de sobre las preferencias reales de la app.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        d.register(defaults: [
            Key.workMinutes.rawValue: 25,
            Key.shortBreakMinutes.rawValue: 5,
            Key.longBreakMinutes.rawValue: 15,
            Key.sessionsBeforeLongBreak.rawValue: 4,
            Key.dailyGoal.rawValue: 8,
            Key.dailyGoalMinutes.rawValue: 120,
            Key.suggestFocusMode.rawValue: false,
            Key.autoStartBreaks.rawValue: true,
            Key.autoStartWork.rawValue: false,
            Key.keepScreenAwake.rawValue: true,
            Key.hapticsEnabled.rawValue: true,
            Key.chimeEnabled.rawValue: true,
            Key.soundID.rawValue: SoundKind.none.id,
            Key.soundVolume.rawValue: 0.55,
            Key.binauralBeatHz.rawValue: 10.0,
            Key.binauralCarrierHz.rawValue: 200.0,
            Key.binauralNoiseMix.rawValue: 0.35,
            Key.breakFollowsWorkSound.rawValue: true,
            Key.breakSoundID.rawValue: SoundKind.none.id,
            Key.mixWithOtherAudio.rawValue: true,
            Key.immersionModeID.rawValue: ImmersionMode.afterDelay.id,
        ])
        workMinutes = d.integer(forKey: Key.workMinutes.rawValue)
        shortBreakMinutes = d.integer(forKey: Key.shortBreakMinutes.rawValue)
        longBreakMinutes = d.integer(forKey: Key.longBreakMinutes.rawValue)
        sessionsBeforeLongBreak = d.integer(forKey: Key.sessionsBeforeLongBreak.rawValue)
        let legacyGoal = d.integer(forKey: Key.dailyGoal.rawValue)
        dailyGoal = max(1, legacyGoal)
        dailyGoalModeID = d.string(forKey: Key.dailyGoalModeID.rawValue)
            ?? (legacyGoal == 0 ? DailyGoalMode.disabled.rawValue : DailyGoalMode.blocks.rawValue)
        dailyGoalMinutes = max(1, d.integer(forKey: Key.dailyGoalMinutes.rawValue))
        lastGoalCelebrationDay = d.object(forKey: Key.lastGoalCelebrationDay.rawValue) as? Date
        suggestFocusMode = d.bool(forKey: Key.suggestFocusMode.rawValue)
        autoStartBreaks = d.bool(forKey: Key.autoStartBreaks.rawValue)
        autoStartWork = d.bool(forKey: Key.autoStartWork.rawValue)
        keepScreenAwake = d.bool(forKey: Key.keepScreenAwake.rawValue)
        hapticsEnabled = d.bool(forKey: Key.hapticsEnabled.rawValue)
        chimeEnabled = d.bool(forKey: Key.chimeEnabled.rawValue)
        soundID = SoundKind.none.id
        soundVolume = d.double(forKey: Key.soundVolume.rawValue)
        binauralBeatHz = d.double(forKey: Key.binauralBeatHz.rawValue)
        binauralCarrierHz = d.double(forKey: Key.binauralCarrierHz.rawValue)
        binauralNoiseMix = d.double(forKey: Key.binauralNoiseMix.rawValue)
        breakFollowsWorkSound = d.bool(forKey: Key.breakFollowsWorkSound.rawValue)
        breakSoundID = SoundKind.none.id
        mixWithOtherAudio = d.bool(forKey: Key.mixWithOtherAudio.rawValue)
        immersionModeID = d.string(forKey: Key.immersionModeID.rawValue) ?? ImmersionMode.afterDelay.id
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    var sound: SoundKind {
        get { SoundKind(id: soundID) ?? .none }
        set { soundID = newValue.id }
    }

    var breakSound: SoundKind {
        get { SoundKind(id: breakSoundID) ?? .none }
        set { breakSoundID = newValue.id }
    }

    var immersionMode: ImmersionMode {
        get { ImmersionMode(rawValue: immersionModeID) ?? .afterDelay }
        set { immersionModeID = newValue.rawValue }
    }

    /// Qué suena en cada fase.
    func sound(for phase: PomodoroPhase) -> SoundKind {
        guard phase.isBreak, !breakFollowsWorkSound else { return sound }
        return breakSound
    }

    /// Todo lo que el motor de audio necesita saber, ya resuelto para la fase.
    func soundConfig(for phase: PomodoroPhase) -> SoundConfig {
        SoundConfig(
            kind: sound(for: phase),
            volume: soundVolume,
            beatHz: binauralBeatHz,
            carrierHz: binauralCarrierHz,
            noiseMix: binauralNoiseMix,
            mixWithOthers: mixWithOtherAudio
        )
    }

    func setDuration(minutes: Int, for phase: PomodoroPhase) {
        switch phase {
        case .work: workMinutes = minutes
        case .shortBreak: shortBreakMinutes = minutes
        case .longBreak: longBreakMinutes = minutes
        }
    }

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: TimeInterval(workMinutes * 60)
        case .shortBreak: TimeInterval(shortBreakMinutes * 60)
        case .longBreak: TimeInterval(longBreakMinutes * 60)
        }
    }
}

/// Cuándo se retiran los controles para dejar solo la cuenta atrás.
enum ImmersionMode: String, CaseIterable, Identifiable {
    case never
    case afterDelay
    case immediate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Nunca"
        case .afterDelay: "A los 6 s"
        case .immediate: "Al empezar"
        }
    }

    var delay: Duration? {
        switch self {
        case .never: nil
        case .afterDelay: .seconds(6)
        case .immediate: .seconds(0.4)
        }
    }
}
