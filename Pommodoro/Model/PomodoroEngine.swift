import Foundation
import Observation

/// Reloj del ciclo Pomodoro.
///
/// La cuenta atrás se apoya en una fecha de fin absoluta en lugar de ir restando
/// en cada tick, de modo que sobrevive a que la app pase a segundo plano o a que
/// el temporizador se retrase: al volver, basta con recalcular contra el reloj.
/// Esa misma fecha se guarda en disco, así que también sobrevive a que el
/// sistema descargue la app a mitad de un bloque.
@MainActor
@Observable
final class PomodoroEngine {
    enum RunState: String { case idle, running, paused }

    private(set) var phase: PomodoroPhase = .work
    private(set) var runState: RunState = .idle
    private(set) var remaining: TimeInterval
    /// Pomodoros de trabajo completados dentro del ciclo actual.
    private(set) var completedInCycle: Int = 0
    /// Pomodoros completados hoy. Se reinicia al cambiar el día natural.
    private(set) var completedTotal: Int = 0

    /// En qué estás trabajando. Un pomodoro sin intención es una cuenta atrás.
    private(set) var currentTask: String = ""
    /// Interrupciones marcadas durante el bloque en curso.
    private(set) var externalInterruptions: Int = 0
    private(set) var internalInterruptions: Int = 0

    private let settings: AppSettings
    private let effects: PomodoroEffects
    private let liveActivity: LiveActivityManaging
    private let recorder: SessionRecording?
    private let store: UserDefaults
    private let calendar: Calendar
    /// Fuente de tiempo inyectable: los tests necesitan mover el reloj.
    private let now: () -> Date

    private var endDate: Date?
    private var ticker: Timer?
    /// Cuándo empezó de verdad la fase en curso. `nil` = aún no ha arrancado.
    private var phaseStartedAt: Date?
    private var phaseDuration: TimeInterval?

    /// Por debajo de esto no se registra nada: son toques en falso, no sesiones.
    private static let minimumRecordableSeconds: TimeInterval = 30

    init(
        settings: AppSettings = .shared,
        effects: PomodoroEffects? = nil,
        liveActivity: LiveActivityManaging? = nil,
        recorder: SessionRecording? = nil,
        store: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.settings = settings
        // El valor por defecto se construye aquí y no en la firma: `SystemEffects`
        // está aislado al hilo principal y los argumentos por defecto no lo están.
        self.effects = effects ?? SystemEffects()
        self.liveActivity = liveActivity ?? LiveActivityController.shared
        self.recorder = recorder
        self.store = store
        self.calendar = calendar
        self.now = now
        self.remaining = settings.duration(for: .work)
        restore()
        refreshLiveActivity()
    }

    var totalForPhase: TimeInterval {
        max(phaseDuration ?? settings.duration(for: phase), 1)
    }

    /// Trabajo de la sesión todavía no guardada. No incluye pausas ni descansos.
    var currentDayWorkSeconds: TimeInterval {
        guard phase == .work, let phaseStartedAt,
              calendar.isDate(phaseStartedAt, inSameDayAs: now()) else { return 0 }
        return max(0, totalForPhase - remaining)
    }

    var progress: Double {
        1 - min(max(remaining / totalForPhase, 0), 1)
    }

    var isRunning: Bool { runState == .running }

    // MARK: - Control

    func toggle() {
        switch runState {
        case .running: pause()
        case .paused, .idle: start()
        }
    }

    func start() {
        guard runState != .running else { return }
        if remaining <= 0 { remaining = totalForPhase }
        if phaseStartedAt == nil {
            phaseDuration = totalForPhase
            phaseStartedAt = now()
        }
        let end = now().addingTimeInterval(remaining)
        endDate = end
        runState = .running
        scheduleTicker()
        effects.scheduleEnd(for: phase, at: end)
        applyIdleTimer()
        persist()
        effects.haptic(.start)
    }

    func pause() {
        guard runState == .running else { return }
        sync()
        // `sync` puede haber cerrado la fase justo en este instante; si ya no
        // estamos en marcha, no hay nada que pausar.
        guard runState == .running else { return }
        runState = .paused
        endDate = nil
        invalidateTicker()
        effects.cancelScheduledEnd()
        applyIdleTimer()
        persist()
        effects.haptic(.stop)
    }

    /// Reinicia la fase actual sin tocar el contador de sesiones.
    /// Lo que llevabas hecho se registra como abandonado: tirar seis minutos a
    /// la basura es un dato, no un no-evento.
    func reset() {
        sync()
        recordIfWorthIt(outcome: .abandoned)
        invalidateTicker()
        effects.cancelScheduledEnd()
        endDate = nil
        runState = .idle
        clearPhaseTracking()
        remaining = totalForPhase
        applyIdleTimer()
        persist()
        effects.haptic(.stop)
    }

    /// Salta a la fase siguiente sin contar la actual como completada.
    func skip() {
        sync()
        recordIfWorthIt(outcome: .abandoned)
        advance(countAsCompleted: false, autoStart: false)
        effects.haptic(.skip)
    }

    // MARK: - Tarea e interrupciones

    func setTask(_ task: String) {
        currentTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    /// Marca una interrupción sin detener el contador: el gesto de registrarla
    /// es el que reduce las siguientes, pararse a gestionarla no.
    func markInterruption(external: Bool) {
        guard runState == .running else { return }
        if external { externalInterruptions += 1 } else { internalInterruptions += 1 }
        persist()
        effects.haptic(.skip)
    }

    var interruptionCount: Int { externalInterruptions + internalInterruptions }

    func recentTasks(limit: Int = 6) -> [String] {
        recorder?.recentTasks(limit: limit) ?? []
    }

    /// Rango que cubre una vuelta completa al anillo.
    static let ringMinutes = 1...60

    /// Fija la duración de la fase actual, tal como la deja el arrastre sobre
    /// el anillo antes de empezar. Durante una sesión, también en pausa, se
    /// conserva la duración inicial para no alterar el esfuerzo ya trabajado.
    func setCurrentPhaseDuration(minutes: Int) {
        guard runState == .idle else { return }
        let clamped = min(max(minutes, Self.ringMinutes.lowerBound), Self.ringMinutes.upperBound)
        guard clamped != Int(totalForPhase / 60) else { return }
        settings.setDuration(minutes: clamped, for: phase)
        remaining = totalForPhase
        persist()
    }

    /// Reaplica las duraciones tras un cambio en ajustes.
    func settingsDidChange() {
        guard runState == .idle else { return }
        remaining = totalForPhase
        persist()
    }

    // MARK: - Ciclo de vida de la escena

    /// Recalcula el tiempo restante contra el reloj del sistema.
    /// Se llama en cada tick y al volver a primer plano.
    func sync() {
        refreshDayIfNeeded()
        guard runState == .running, let endDate else { return }
        let left = endDate.timeIntervalSince(now())
        if left <= 0 {
            remaining = 0
            finishPhase(announce: true)
        } else {
            remaining = left
        }
    }

    // MARK: - Persistencia

    private enum Key {
        static let phase = "engine.phase"
        static let runState = "engine.runState"
        static let remaining = "engine.remaining"
        static let endDate = "engine.endDate"
        static let completedInCycle = "engine.completedInCycle"
        static let completedTotal = "engine.completedTotal"
        static let totalDay = "engine.completedTotalDay"
        static let task = "engine.currentTask"
        static let phaseStartedAt = "engine.phaseStartedAt"
        static let phaseDuration = "engine.phaseDuration"
        static let externalInterruptions = "engine.externalInterruptions"
        static let internalInterruptions = "engine.internalInterruptions"
    }

    private func persist() {
        store.set(phaseDuration, forKey: Key.phaseDuration)
        store.set(phase.rawValue, forKey: Key.phase)
        store.set(runState.rawValue, forKey: Key.runState)
        store.set(remaining, forKey: Key.remaining)
        store.set(completedInCycle, forKey: Key.completedInCycle)
        store.set(completedTotal, forKey: Key.completedTotal)
        store.set(calendar.startOfDay(for: now()), forKey: Key.totalDay)
        store.set(currentTask, forKey: Key.task)
        store.set(externalInterruptions, forKey: Key.externalInterruptions)
        store.set(internalInterruptions, forKey: Key.internalInterruptions)
        if let endDate {
            store.set(endDate, forKey: Key.endDate)
        } else {
            store.removeObject(forKey: Key.endDate)
        }
        if let phaseStartedAt {
            store.set(phaseStartedAt, forKey: Key.phaseStartedAt)
        } else {
            store.removeObject(forKey: Key.phaseStartedAt)
        }
        refreshLiveActivity()
    }

    /// Only publish state transitions, never the 5 Hz ticker. The system owns
    /// countdown rendering, including while our process is suspended.
    func refreshLiveActivity() {
        guard runState != .idle else {
            liveActivity.synchronize(nil)
            return
        }
        liveActivity.synchronize(TimerActivityState(
            phaseTitle: phase.title,
            symbol: phase.symbol,
            isBreak: phase.isBreak,
            task: phase.isBreak ? "" : String(currentTask.prefix(120)),
            timerStart: endDate.map { $0.addingTimeInterval(-totalForPhase) },
            endDate: endDate,
            remaining: runState == .paused ? remaining : 0
        ))
    }

    /// Recompone el estado guardado. Si la fase terminó mientras la app no
    /// existía, la da por completada y deja la siguiente lista, en pausa: el
    /// usuario ya recibió la notificación y decide él cuándo seguir.
    private func restore() {
        guard let rawPhase = store.string(forKey: Key.phase),
              let savedPhase = PomodoroPhase(rawValue: rawPhase)
        else {
            remaining = totalForPhase
            return
        }

        phase = savedPhase
        currentTask = store.string(forKey: Key.task) ?? ""
        phaseStartedAt = store.object(forKey: Key.phaseStartedAt) as? Date
        phaseDuration = store.object(forKey: Key.phaseDuration) as? Double
        externalInterruptions = store.integer(forKey: Key.externalInterruptions)
        internalInterruptions = store.integer(forKey: Key.internalInterruptions)
        completedInCycle = store.integer(forKey: Key.completedInCycle)
        completedTotal = store.integer(forKey: Key.completedTotal)
        refreshDayIfNeeded()

        let savedState = store.string(forKey: Key.runState).flatMap(RunState.init(rawValue:)) ?? .idle
        switch savedState {
        case .running:
            guard let end = store.object(forKey: Key.endDate) as? Date else {
                remaining = totalForPhase
                runState = .idle
                return
            }
            let left = end.timeIntervalSince(now())
            if left > 0 {
                endDate = end
                remaining = left
                runState = .running
                scheduleTicker()
                applyIdleTimer()
            } else {
                // La fase acabó estando la app cerrada: sin campana ni vibración,
                // porque el aviso ya salió por la notificación en su momento.
                remaining = 0
                finishPhase(announce: false)
            }

        case .paused:
            remaining = max(store.double(forKey: Key.remaining), 0)
            if remaining <= 0 { remaining = totalForPhase }
            runState = .paused

        case .idle:
            clearPhaseTracking()
            remaining = totalForPhase
            runState = .idle
        }
    }

    /// Pone a cero el recuento de hoy cuando cambia el día natural.
    private func refreshDayIfNeeded() {
        let today = calendar.startOfDay(for: now())
        let savedDay = store.object(forKey: Key.totalDay) as? Date
        guard let savedDay else {
            store.set(today, forKey: Key.totalDay)
            return
        }
        guard !calendar.isDate(savedDay, inSameDayAs: today) else { return }
        completedTotal = 0
        store.set(0, forKey: Key.completedTotal)
        store.set(today, forKey: Key.totalDay)
    }

    // MARK: - Interno

    private func scheduleTicker() {
        invalidateTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func invalidateTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func finishPhase(announce: Bool) {
        invalidateTicker()
        endDate = nil
        record(outcome: .completed, actualSeconds: totalForPhase)
        let wasWork = phase == .work
        if announce {
            // El fondo se retira primero: la campana no debe llegar encima de
            // un paisaje sonoro a todo volumen.
            effects.fadeOutAmbience()
            if settings.chimeEnabled {
                effects.playChime(wasWork ? .breakStart : .workStart)
            }
            effects.haptic(.phaseComplete)
        }
        let autoStart = announce && (wasWork ? settings.autoStartBreaks : settings.autoStartWork)
        advance(countAsCompleted: true, autoStart: autoStart)
    }

    private func advance(countAsCompleted: Bool, autoStart: Bool) {
        invalidateTicker()
        effects.cancelScheduledEnd()
        endDate = nil

        if phase == .work {
            if countAsCompleted {
                completedInCycle += 1
                completedTotal += 1
            }
            let target = max(settings.sessionsBeforeLongBreak, 1)
            if completedInCycle >= target {
                phase = .longBreak
                completedInCycle = 0
            } else {
                phase = .shortBreak
            }
        } else {
            phase = .work
        }

        clearPhaseTracking()
        remaining = totalForPhase
        runState = .idle
        if autoStart {
            start()
        } else {
            applyIdleTimer()
            persist()
        }
    }

    /// Registra la fase en curso solo si llegó a correr lo suficiente.
    private func recordIfWorthIt(outcome: SessionOutcome) {
        guard phaseStartedAt != nil else { return }
        let elapsed = max(totalForPhase - remaining, 0)
        guard elapsed >= Self.minimumRecordableSeconds else { return }
        record(outcome: outcome, actualSeconds: elapsed)
    }

    private func record(outcome: SessionOutcome, actualSeconds: TimeInterval) {
        guard let recorder, let startedAt = phaseStartedAt else { return }
        let task = currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
        recorder.record(
            SessionRecord(
                startedAt: startedAt,
                endedAt: now(),
                phase: phase,
                outcome: outcome,
                plannedSeconds: totalForPhase,
                actualSeconds: actualSeconds,
                task: (phase == .work && !task.isEmpty) ? task : nil,
                externalInterruptions: externalInterruptions,
                internalInterruptions: internalInterruptions
            )
        )
    }

    private func clearPhaseTracking() {
        phaseStartedAt = nil
        phaseDuration = nil
        externalInterruptions = 0
        internalInterruptions = 0
    }

    private func applyIdleTimer() {
        effects.setIdleTimerDisabled(settings.keepScreenAwake && runState == .running)
    }
}

extension TimeInterval {
    /// `mm:ss`, o `h:mm:ss` a partir de una hora.
    var clockString: String {
        let total = Int(rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// La misma cuenta atrás dicha en voz alta, para VoiceOver. «02:05» leído
    /// como cifras no significa nada; «2 minutos y 5 segundos» sí.
    var spokenString: String {
        let total = Int(rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hora" : "horas")") }
        if m > 0 { parts.append("\(m) \(m == 1 ? "minuto" : "minutos")") }
        if s > 0 || parts.isEmpty { parts.append("\(s) \(s == 1 ? "segundo" : "segundos")") }
        return parts.joined(separator: " y ")
    }
}
