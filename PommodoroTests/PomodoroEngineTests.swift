import Foundation
import SwiftData
import Testing

@testable import Pommodoro

// MARK: - Dobles

@MainActor
final class SpyLiveActivity: LiveActivityManaging {
    var states: [TimerActivityState?] = []
    func synchronize(_ state: TimerActivityState?) { states.append(state) }
    var latest: TimerActivityState? { states.last ?? nil }
}

/// Reloj movible: los tests necesitan saltar al final de un bloque sin esperar
/// veinticinco minutos.
final class TestClock: @unchecked Sendable {
    var now: Date
    /// Arranca a media mañana UTC a propósito: un ciclo completo suma casi dos
    /// horas, y empezando de noche cruzaría la medianoche y el contador de «hoy»
    /// se reiniciaría en mitad del test (que es justo lo que debe hacer).
    init(_ start: Date = Date(timeIntervalSince1970: 1_699_953_200)) { now = start }
    func advance(_ seconds: TimeInterval) { now += seconds }
}

/// Guarda lo registrado en memoria, para poder afirmar sobre ello.
@MainActor
final class SpyRecorder: SessionRecording {
    private(set) var records: [SessionRecord] = []
    var tasks: [String] = []

    func record(_ record: SessionRecord) { records.append(record) }
    func recentTasks(limit: Int) -> [String] { Array(tasks.prefix(limit)) }

    var workRecords: [SessionRecord] { records.filter { $0.phase == .work } }
}

/// Apunta los efectos que pide el motor en vez de ejecutarlos.
@MainActor
final class SpyEffects: PomodoroEffects {
    private(set) var scheduled: [(phase: PomodoroPhase, date: Date)] = []
    private(set) var cancelCount = 0
    private(set) var chimes: [ChimeKind] = []
    private(set) var fadeOuts = 0
    private(set) var haptics: [HapticCue] = []
    private(set) var idleTimerDisabled = false

    func scheduleEnd(for phase: PomodoroPhase, at date: Date) {
        scheduled.append((phase, date))
    }
    func cancelScheduledEnd() { cancelCount += 1 }
    func playChime(_ kind: ChimeKind) { chimes.append(kind) }
    func fadeOutAmbience() { fadeOuts += 1 }
    func haptic(_ cue: HapticCue) { haptics.append(cue) }
    func setIdleTimerDisabled(_ disabled: Bool) { idleTimerDisabled = disabled }
}

// MARK: - Andamiaje

@MainActor
struct Harness {
    let settings: AppSettings
    let store: UserDefaults
    let clock: TestClock
    let effects: SpyEffects
    let liveActivity = SpyLiveActivity()
    let recorder: SpyRecorder
    let calendar: Calendar

    /// Cada caso trabaja sobre un dominio de preferencias propio, así que los
    /// tests no se pisan entre ellos ni tocan los ajustes reales.
    init(
        work: Int = 25,
        short: Int = 5,
        long: Int = 15,
        blocks: Int = 4,
        autoStartBreaks: Bool = false,
        autoStartWork: Bool = false,
        clock: TestClock = TestClock()
    ) {
        let suite = "test.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: store)
        settings.workMinutes = work
        settings.shortBreakMinutes = short
        settings.longBreakMinutes = long
        settings.sessionsBeforeLongBreak = blocks
        settings.autoStartBreaks = autoStartBreaks
        settings.autoStartWork = autoStartWork
        settings.chimeEnabled = true
        self.clock = clock
        self.effects = SpyEffects()
        self.recorder = SpyRecorder()

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = cal
    }

    func makeEngine() -> PomodoroEngine {
        PomodoroEngine(
            settings: settings,
            effects: effects,
            liveActivity: liveActivity,
            recorder: recorder,
            store: store,
            calendar: calendar,
            now: { [clock] in clock.now }
        )
    }

    /// Lleva el reloj más allá del final de la fase en marcha y avisa al motor.
    func runOutCurrentPhase(_ engine: PomodoroEngine) {
        clock.advance(engine.remaining + 1)
        engine.sync()
    }
}

// MARK: - Ciclo

@MainActor
@Suite("Ciclo de fases")
struct CycleTests {

    @Test("Un bloque de trabajo terminado lleva al descanso corto y cuenta")
    func workLeadsToShortBreak() {
        let h = Harness()
        let engine = h.makeEngine()

        engine.start()
        h.runOutCurrentPhase(engine)

        #expect(engine.phase == .shortBreak)
        #expect(engine.completedInCycle == 1)
        #expect(engine.completedTotal == 1)
        #expect(engine.runState == .idle)
        #expect(h.effects.chimes == [.breakStart])
    }

    @Test("El cuarto bloque lleva al descanso largo y reinicia el ciclo")
    func fourthBlockLeadsToLongBreak() {
        let h = Harness(blocks: 4)
        let engine = h.makeEngine()

        for expected in 1...3 {
            engine.start()
            h.runOutCurrentPhase(engine)
            #expect(engine.phase == .shortBreak)
            #expect(engine.completedInCycle == expected)
            engine.start()          // el descanso
            h.runOutCurrentPhase(engine)
            #expect(engine.phase == .work)
        }

        engine.start()
        h.runOutCurrentPhase(engine)

        #expect(engine.phase == .longBreak)
        #expect(engine.completedInCycle == 0, "el ciclo vuelve a empezar")
        #expect(engine.completedTotal == 4)
    }

    @Test("Saltar no cuenta el bloque como completado")
    func skipDoesNotCount() {
        let h = Harness()
        let engine = h.makeEngine()

        engine.start()
        engine.skip()

        #expect(engine.phase == .shortBreak)
        #expect(engine.completedInCycle == 0)
        #expect(engine.completedTotal == 0)
        #expect(h.effects.chimes.isEmpty, "saltar no es un logro, no suena")
    }

    @Test("Terminar un descanso vuelve al trabajo sin sumar bloques")
    func breakReturnsToWork() {
        let h = Harness()
        let engine = h.makeEngine()

        engine.start()
        h.runOutCurrentPhase(engine)   // trabajo -> descanso
        let afterWork = engine.completedTotal

        engine.start()
        h.runOutCurrentPhase(engine)   // descanso -> trabajo

        #expect(engine.phase == .work)
        #expect(engine.completedTotal == afterWork)
        #expect(h.effects.chimes == [.breakStart, .workStart])
    }

    @Test("Con encadenado automático el descanso arranca solo")
    func autoStartBreak() {
        let h = Harness(autoStartBreaks: true)
        let engine = h.makeEngine()

        engine.start()
        h.runOutCurrentPhase(engine)

        #expect(engine.phase == .shortBreak)
        #expect(engine.runState == .running)
    }

    @Test("Reiniciar devuelve la fase entera sin tocar el recuento")
    func resetKeepsCount() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()

        engine.start()
        h.runOutCurrentPhase(engine)   // 1 bloque hecho, ahora en descanso
        engine.start()
        h.clock.advance(60)
        engine.sync()
        engine.reset()

        #expect(engine.runState == .idle)
        #expect(engine.remaining == 5 * 60)
        #expect(engine.completedTotal == 1)
    }

    @Test("Pausar conserva el tiempo que quedaba")
    func pauseKeepsRemaining() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()

        engine.start()
        h.clock.advance(600)
        engine.pause()

        #expect(engine.runState == .paused)
        #expect(abs(engine.remaining - 900) < 0.01)

        // El reloj sigue corriendo, pero en pausa no descuenta.
        h.clock.advance(300)
        engine.sync()
        #expect(abs(engine.remaining - 900) < 0.01)
    }

    @Test("El progreso va de 0 a 1 dentro de la fase")
    func progress() {
        let h = Harness(work: 10)
        let engine = h.makeEngine()

        #expect(engine.progress == 0)
        engine.start()
        h.clock.advance(300)
        engine.sync()
        #expect(abs(engine.progress - 0.5) < 0.001)
    }
}

// MARK: - Persistencia

@MainActor
@Suite("El temporizador sobrevive a que se cierre la app")
struct PersistenceTests {

    @Test("Un bloque en marcha se recupera con el tiempo correcto")
    func runningSurvivesRelaunch() {
        let h = Harness(work: 50)
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(600)
        engine.sync()

        // Simula que iOS descarga la app: motor nuevo, mismo almacén.
        let revived = h.makeEngine()

        #expect(revived.runState == .running)
        #expect(revived.phase == .work)
        #expect(abs(revived.remaining - 2400) < 1.0)
    }

    @Test("Una pausa se recupera como pausa")
    func pausedSurvivesRelaunch() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(300)
        engine.pause()

        let revived = h.makeEngine()

        #expect(revived.runState == .paused)
        #expect(abs(revived.remaining - 1200) < 1.0)
    }

    @Test("Si la fase terminó estando cerrada, se da por hecha y no vuelve a sonar")
    func phaseThatEndedWhileClosed() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()

        // La app desaparece y vuelve media hora después.
        h.clock.advance(30 * 60)
        let revived = h.makeEngine()

        #expect(revived.phase == .shortBreak, "el bloque se da por completado")
        #expect(revived.completedTotal == 1)
        #expect(revived.runState == .idle, "espera al usuario, no arranca solo")
        #expect(h.effects.chimes.isEmpty, "el aviso ya salió por la notificación")
    }

    @Test("La posición dentro del ciclo también se recupera")
    func cyclePositionSurvives() {
        let h = Harness(blocks: 4)
        let engine = h.makeEngine()
        engine.start()
        h.runOutCurrentPhase(engine)   // 1 bloque
        engine.start()
        h.runOutCurrentPhase(engine)   // vuelta al trabajo

        let revived = h.makeEngine()

        #expect(revived.completedInCycle == 1)
        #expect(revived.phase == .work)
    }

    @Test("Un almacén vacío arranca limpio")
    func freshInstall() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()

        #expect(engine.phase == .work)
        #expect(engine.runState == .idle)
        #expect(engine.remaining == 25 * 60)
        #expect(engine.completedTotal == 0)
    }
}

// MARK: - El contador de hoy

@MainActor
@Suite("El recuento de hoy dice la verdad")
struct DailyCountTests {

    @Test("Los bloques del mismo día se conservan al reabrir")
    func sameDayKeepsCount() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.runOutCurrentPhase(engine)
        #expect(engine.completedTotal == 1)

        h.clock.advance(60 * 60)        // una hora después, mismo día
        let revived = h.makeEngine()

        #expect(revived.completedTotal == 1)
    }

    @Test("Al cambiar el día natural el recuento vuelve a cero")
    func newDayResetsCount() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.runOutCurrentPhase(engine)
        #expect(engine.completedTotal == 1)

        h.clock.advance(36 * 60 * 60)   // día siguiente
        let revived = h.makeEngine()

        #expect(revived.completedTotal == 0)
    }

    @Test("Si el día cambia con la app abierta, el contador se pone al día")
    func dayRollsOverWhileOpen() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.runOutCurrentPhase(engine)
        #expect(engine.completedTotal == 1)

        h.clock.advance(36 * 60 * 60)
        engine.sync()

        #expect(engine.completedTotal == 0)
    }
}

// MARK: - Formato

@Suite("Formato del reloj")
struct ClockFormatTests {

    @Test("Debajo de una hora se muestra mm:ss")
    func minutesAndSeconds() {
        #expect(TimeInterval(1500).clockString == "25:00")
        #expect(TimeInterval(65).clockString == "01:05")
        #expect(TimeInterval(0).clockString == "00:00")
    }

    @Test("A partir de una hora aparecen las horas")
    func withHours() {
        #expect(TimeInterval(3600).clockString == "1:00:00")
        #expect(TimeInterval(5430).clockString == "1:30:30")
    }

    @Test("Los segundos parciales redondean hacia arriba")
    func roundsUp() {
        // Si quedan 24,3 s el reloj marca 25, no 24: llegar a 00:00 debe
        // coincidir con el final real, no anticiparlo.
        #expect(TimeInterval(24.3).clockString == "00:25")
    }

    @Test("VoiceOver lee el tiempo en palabras")
    func spoken() {
        #expect(TimeInterval(1500).spokenString == "25 minutos")
        #expect(TimeInterval(65).spokenString == "1 minuto y 5 segundos")
        #expect(TimeInterval(1).spokenString == "1 segundo")
        #expect(TimeInterval(0).spokenString == "0 segundos")
        #expect(TimeInterval(3660).spokenString == "1 hora y 1 minuto")
    }
}

// MARK: - Duración desde el anillo

@MainActor
@Suite("Fijar la duración arrastrando el anillo")
struct RingDurationTests {

    @Test("Fijar minutos cambia la fase actual y el tiempo mostrado")
    func setsCurrentPhase() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()

        engine.setCurrentPhaseDuration(minutes: 40)

        #expect(engine.remaining == 40 * 60)
        #expect(h.settings.workMinutes == 40)
        #expect(h.settings.shortBreakMinutes == 5, "el descanso no se toca")
    }

    @Test("Durante un descanso ajusta el descanso, no el trabajo")
    func setsBreakPhase() {
        let h = Harness(work: 25, short: 5)
        let engine = h.makeEngine()
        engine.start()
        h.runOutCurrentPhase(engine)          // ahora en descanso corto

        engine.setCurrentPhaseDuration(minutes: 12)

        #expect(h.settings.shortBreakMinutes == 12)
        #expect(h.settings.workMinutes == 25)
        #expect(engine.remaining == 12 * 60)
    }

    @Test("Con el reloj en marcha el arrastre no hace nada")
    func ignoredWhileRunning() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(60)
        engine.sync()

        engine.setCurrentPhaseDuration(minutes: 50)

        #expect(h.settings.workMinutes == 25)
        #expect(abs(engine.remaining - 1440) < 1)
    }

    @Test("Los valores fuera de rango se recortan a una vuelta del anillo")
    func clampsToRing() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()

        engine.setCurrentPhaseDuration(minutes: 0)
        #expect(h.settings.workMinutes == PomodoroEngine.ringMinutes.lowerBound)

        engine.setCurrentPhaseDuration(minutes: 999)
        #expect(h.settings.workMinutes == PomodoroEngine.ringMinutes.upperBound)
    }

    @Test("La duración fijada sobrevive a que se cierre la app")
    func survivesRelaunch() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.setCurrentPhaseDuration(minutes: 45)

        let revived = h.makeEngine()

        #expect(revived.remaining == 45 * 60)
    }
}

// MARK: - Sonido por fase

@MainActor
@Suite("Qué suena en cada fase")
struct PhaseSoundTests {

    @Test("Por defecto el descanso hereda el sonido de concentración")
    func breakFollowsWorkByDefault() {
        let h = Harness()
        h.settings.sound = .rain

        #expect(h.settings.sound(for: .work) == .rain)
        #expect(h.settings.sound(for: .shortBreak) == .rain)
        #expect(h.settings.sound(for: .longBreak) == .rain)
    }

    @Test("Al separarlos, cada fase mantiene el suyo")
    func breakCanDiffer() {
        let h = Harness()
        h.settings.sound = .rain
        h.settings.breakFollowsWorkSound = false
        h.settings.breakSound = .none

        #expect(h.settings.sound(for: .work) == .rain)
        #expect(h.settings.sound(for: .shortBreak) == .none)
    }

    @Test("La configuración de audio se resuelve para la fase pedida")
    func configResolvesPhase() {
        let h = Harness()
        h.settings.sound = .ocean
        h.settings.breakFollowsWorkSound = false
        h.settings.breakSound = .brown
        h.settings.soundVolume = 0.4

        #expect(h.settings.soundConfig(for: .work).kind == .ocean)
        #expect(h.settings.soundConfig(for: .shortBreak).kind == .brown)
        #expect(h.settings.soundConfig(for: .work).volume == 0.4)
    }

    @Test("Los binaurales nunca se mezclan con otro audio")
    func binauralNeverMixes() {
        let mixing = SoundConfig(kind: .rain, mixWithOthers: true)
        let binaural = SoundConfig(kind: .binaural, mixWithOthers: true)

        #expect(mixing.allowsMixing)
        #expect(!binaural.allowsMixing, "los tonos se presentan en exclusiva")
    }
}

// MARK: - Fundido de fase

@MainActor
@Suite("El fondo se retira antes de la campana")
struct FadeTests {

    @Test("Al cerrar una fase se pide el fundido antes de sonar la campana")
    func fadesBeforeChime() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.runOutCurrentPhase(engine)

        #expect(h.effects.fadeOuts == 1)
        #expect(h.effects.chimes == [.breakStart])
    }

    @Test("Saltar a mano no provoca fundido ni campana")
    func skipDoesNotFade() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        engine.skip()

        #expect(h.effects.fadeOuts == 0)
        #expect(h.effects.chimes.isEmpty)
    }
}

// MARK: - Propuestas de descanso

@Suite("Propuestas de descanso")
struct BreakSuggestionTests {

    @Test("La propuesta es estable durante el mismo descanso")
    func stableWithinBreak() {
        let a = BreakSuggestion.forBreak(phase: .shortBreak, seed: 3)
        let b = BreakSuggestion.forBreak(phase: .shortBreak, seed: 3)
        #expect(a == b)
    }

    @Test("Descansos consecutivos proponen cosas distintas")
    func variesBetweenBreaks() {
        let a = BreakSuggestion.forBreak(phase: .shortBreak, seed: 0)
        let b = BreakSuggestion.forBreak(phase: .shortBreak, seed: 1)
        #expect(a != b)
    }

    @Test("El descanso largo tiene propuestas propias")
    func longBreakHasOwnPool() {
        let long = BreakSuggestion.forBreak(phase: .longBreak, seed: 0)
        #expect(BreakSuggestion.long.contains(long))
        #expect(!BreakSuggestion.short.contains(long))
    }

    @Test("Cualquier semilla devuelve algo, también negativa")
    func handlesAnySeed() {
        for seed in [-7, -1, 0, 1, 99] {
            let s = BreakSuggestion.forBreak(phase: .shortBreak, seed: seed)
            #expect(!s.title.isEmpty)
        }
    }
}

// MARK: - Tarea del bloque

@MainActor
@Suite("Cada bloque lleva su tarea")
struct TaskTests {

    @Test("La tarea se guarda con la sesión completada")
    func taskTravelsWithSession() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.setTask("Escribir el informe")

        engine.start()
        h.runOutCurrentPhase(engine)

        #expect(h.recorder.workRecords.first?.task == "Escribir el informe")
    }

    @Test("Los espacios sobrantes se recortan")
    func trimsWhitespace() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.setTask("   Revisar el PR  ")
        #expect(engine.currentTask == "Revisar el PR")
    }

    @Test("Sin tarea, la sesión se guarda sin ella y no con una cadena vacía")
    func emptyTaskIsNil() {
        let h = Harness()
        let engine = h.makeEngine()

        engine.start()
        h.runOutCurrentPhase(engine)

        #expect(h.recorder.workRecords.first?.task == nil)
    }

    @Test("La tarea se mantiene entre bloques y sobrevive al cierre de la app")
    func taskPersists() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.setTask("Diseñar la pantalla")

        engine.start()
        h.runOutCurrentPhase(engine)      // pasa a descanso

        #expect(engine.currentTask == "Diseñar la pantalla")
        #expect(h.makeEngine().currentTask == "Diseñar la pantalla")
    }

    @Test("Los descansos no arrastran la tarea del trabajo")
    func breaksHaveNoTask() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.setTask("Escribir")

        engine.start()
        h.runOutCurrentPhase(engine)      // trabajo -> descanso
        engine.start()
        h.runOutCurrentPhase(engine)      // descanso -> trabajo

        let breakRecord = h.recorder.records.first { $0.phase == .shortBreak }
        #expect(breakRecord?.task == nil)
    }
}

// MARK: - Completado frente a abandonado

@MainActor
@Suite("Completado no es lo mismo que abandonado")
struct OutcomeTests {

    @Test("Llegar a cero se registra como completado")
    func completed() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()
        h.runOutCurrentPhase(engine)

        let record = h.recorder.workRecords.first
        #expect(record?.outcome == .completed)
        // Los literales van como Double explícito: dentro de `#expect`, comparar
        // un `Double?` con `25 * 60` infiere el literal como Int y falla aunque
        // el número sea el mismo.
        #expect(record?.actualSeconds == Double(25 * 60))
        #expect(record?.plannedSeconds == Double(25 * 60))
    }

    @Test("Saltar a mitad se registra como abandonado, con lo que duró de verdad")
    func abandonedBySkip() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(600)
        engine.skip()

        let record = h.recorder.workRecords.first
        #expect(record?.outcome == .abandoned)
        #expect(abs((record?.actualSeconds ?? 0) - 600) < 1)
        #expect(record?.plannedSeconds == Double(25 * 60))
    }

    @Test("Reiniciar también abandona: el tiempo tirado es un dato")
    func abandonedByReset() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(420)
        engine.reset()

        #expect(h.recorder.workRecords.first?.outcome == .abandoned)
    }

    @Test("Un bloque que nunca arrancó no deja rastro")
    func neverStartedIsNotRecorded() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.skip()
        #expect(h.recorder.records.isEmpty)
    }

    @Test("Los toques en falso no ensucian el historial")
    func tooShortIsNotRecorded() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(9)
        engine.skip()

        #expect(h.recorder.records.isEmpty, "nueve segundos no son una sesión")
    }
}

// MARK: - Interrupciones

@MainActor
@Suite("Marcar interrupciones")
struct InterruptionTests {

    @Test("Marcar no detiene el contador")
    func doesNotStopTheClock() {
        let h = Harness(work: 25)
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(60)
        engine.sync()

        engine.markInterruption(external: true)

        #expect(engine.runState == .running)
        #expect(abs(engine.remaining - 1440) < 1)
    }

    @Test("Se distinguen las de fuera de las propias")
    func separatesKinds() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        engine.markInterruption(external: true)
        engine.markInterruption(external: false)
        engine.markInterruption(external: false)

        #expect(engine.externalInterruptions == 1)
        #expect(engine.internalInterruptions == 2)
        #expect(engine.interruptionCount == 3)
    }

    @Test("Viajan con la sesión y se ponen a cero en la siguiente")
    func travelWithSessionThenReset() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        engine.markInterruption(external: true)
        engine.markInterruption(external: false)
        h.runOutCurrentPhase(engine)

        let record = h.recorder.workRecords.first
        #expect(record?.externalInterruptions == 1)
        #expect(record?.internalInterruptions == 1)
        #expect(engine.interruptionCount == 0, "el bloque siguiente empieza limpio")
    }

    @Test("Con el reloj parado no se puede marcar nada")
    func ignoredWhenNotRunning() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.markInterruption(external: true)
        #expect(engine.interruptionCount == 0)
    }

    @Test("Las marcas sobreviven a que se cierre la app")
    func survivesRelaunch() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        engine.markInterruption(external: true)

        #expect(h.makeEngine().externalInterruptions == 1)
    }
}

// MARK: - Almacén real

@MainActor
@Suite("El historial en SwiftData", .serialized)
struct SessionStoreTests {

    /// Un único contenedor en memoria para toda la suite. Crear uno por test
    /// para el mismo esquema —conviviendo con el que la app abre al arrancar—
    /// hace que SwiftData reviente dentro de `insert`.
    @MainActor
    private static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: Session.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("No se pudo crear el contenedor de pruebas: \(error)")
        }
    }()

    /// Contexto limpio sobre el contenedor compartido, para que un test no vea
    /// lo que dejó el anterior.
    private func makeRecorder() throws -> (SwiftDataSessionRecorder, ModelContext) {
        let context = ModelContext(Self.container)
        context.autosaveEnabled = false
        try context.delete(model: Session.self)
        try context.save()
        return (SwiftDataSessionRecorder(context: context), context)
    }

    private func sample(
        task: String? = nil,
        outcome: SessionOutcome = .completed,
        startedAt: Date = Date()
    ) -> SessionRecord {
        SessionRecord(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1500),
            phase: .work,
            outcome: outcome,
            plannedSeconds: 1500,
            actualSeconds: 1500,
            task: task,
            externalInterruptions: 0,
            internalInterruptions: 0
        )
    }

    @Test("Lo registrado se puede volver a leer")
    func roundTrip() throws {
        let (recorder, context) = try makeRecorder()
        recorder.record(sample(task: "Escribir", outcome: .abandoned))

        let stored = try context.fetch(FetchDescriptor<Session>())
        #expect(stored.count == 1)
        #expect(stored.first?.task == "Escribir")
        #expect(stored.first?.outcome == .abandoned)
        #expect(stored.first?.phase == .work)
    }

    @Test("Las tareas recientes no se repiten y van de más nueva a más vieja")
    func recentTasksAreDistinct() throws {
        let (recorder, _) = try makeRecorder()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        recorder.record(sample(task: "Informe", startedAt: base))
        recorder.record(sample(task: "Tests", startedAt: base.addingTimeInterval(3600)))
        recorder.record(sample(task: "Informe", startedAt: base.addingTimeInterval(7200)))

        #expect(recorder.recentTasks(limit: 10) == ["Informe", "Tests"])
    }

    @Test("Las sesiones sin tarea no aparecen entre las recientes")
    func ignoresEmptyTasks() throws {
        let (recorder, _) = try makeRecorder()
        recorder.record(sample(task: nil))
        recorder.record(sample(task: "   "))
        recorder.record(sample(task: "Real"))

        #expect(recorder.recentTasks(limit: 10) == ["Real"])
    }

    @Test("El límite se respeta")
    func respectsLimit() throws {
        let (recorder, _) = try makeRecorder()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<10 {
            recorder.record(sample(task: "Tarea \(i)", startedAt: base.addingTimeInterval(Double(i) * 600)))
        }
        #expect(recorder.recentTasks(limit: 3).count == 3)
    }
}

// MARK: - Objetivo diario

@Suite("Objetivo diario")
struct DailyGoalTests {

    @Test("Se dispara justo al cruzar el objetivo")
    func firesOnCross() {
        #expect(DailyGoal.justReached(before: 3, after: 4, goal: 4))
    }

    @Test("No se dispara antes de llegar")
    func notBeforeGoal() {
        #expect(!DailyGoal.justReached(before: 1, after: 2, goal: 4))
    }

    @Test("No se dispara otra vez en los bloques siguientes")
    func notAfterAlreadyPassed() {
        #expect(!DailyGoal.justReached(before: 4, after: 5, goal: 4))
        #expect(!DailyGoal.justReached(before: 5, after: 6, goal: 4))
    }

    @Test("Un objetivo de cero lo desactiva")
    func zeroGoalNeverFires() {
        #expect(!DailyGoal.justReached(before: 0, after: 1, goal: 0))
    }

    @Test("Saltarse un bloque de golpe también cuenta como cruzarlo")
    func jumpingOverGoalStillFires() {
        // Por ejemplo si se cambia el objetivo a mitad de día a un valor menor.
        #expect(DailyGoal.justReached(before: 2, after: 5, goal: 4))
    }
}
