import Foundation
import Testing
@testable import Pommodoro

@MainActor
@Suite("Cuenta atrás en pantalla bloqueada")
struct LiveActivityEngineTests {
    @Test("No hay actividad hasta iniciar una fase; el reloj del sistema recibe una fecha fija")
    func startAndTick() throws {
        let h = Harness()
        let engine = h.makeEngine()
        #expect(h.liveActivity.latest == nil)
        engine.setTask("Escribir propuesta")
        engine.start()
        let state = try #require(h.liveActivity.latest)
        #expect(state.task == "Escribir propuesta")
        #expect(state.endDate == h.clock.now.addingTimeInterval(25 * 60))
        #expect(state.timerInterval?.lowerBound == h.clock.now)
        let updateCount = h.liveActivity.states.count
        h.clock.advance(10)
        engine.sync()
        #expect(h.liveActivity.states.count == updateCount)
        #expect(h.liveActivity.latest == state)
        engine.reset()
    }

    @Test("Pausar congela la cifra; reanudar desplaza la fecha de fin")
    func pauseAndResume() throws {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(60)
        engine.pause()
        let paused = try #require(h.liveActivity.latest)
        #expect(paused.isPaused)
        #expect(paused.timerInterval == nil)
        #expect(paused.remaining == 24 * 60)
        #expect(paused.pausedTime == "24:00")
        h.clock.advance(300)
        engine.start()
        #expect(h.liveActivity.latest?.endDate == h.clock.now.addingTimeInterval(24 * 60))
        engine.reset()
    }

    @Test("Reiniciar, saltar o terminar sin encadenado retira la actividad")
    func terminalTransitions() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        engine.reset()
        #expect(h.liveActivity.latest == nil)
        engine.start()
        engine.skip()
        #expect(h.liveActivity.latest == nil)
        engine.start()
        h.runOutCurrentPhase(engine)
        #expect(h.liveActivity.latest == nil)
    }

    @Test("El descanso automático cambia fase y fecha, sin mostrar la tarea de trabajo")
    func automaticBreak() throws {
        let h = Harness(autoStartBreaks: true)
        let engine = h.makeEngine()
        engine.setTask("Estudiar")
        engine.start()
        h.runOutCurrentPhase(engine)
        let state = try #require(h.liveActivity.latest)
        #expect(state.isBreak)
        #expect(state.phaseTitle == "Descanso")
        #expect(state.task.isEmpty)
        #expect(state.endDate == h.clock.now.addingTimeInterval(5 * 60))
        engine.reset()
    }

    @Test("Reabrir recupera la actividad en marcha y en pausa")
    func restore() {
        let h = Harness()
        let first = h.makeEngine()
        first.start()
        let originalEnd = h.liveActivity.latest?.endDate
        h.clock.advance(45)
        let restored = h.makeEngine()
        #expect(h.liveActivity.latest?.endDate == originalEnd)
        restored.pause()
        let paused = h.makeEngine()
        #expect(h.liveActivity.latest?.remaining == TimeInterval(1455))
        #expect(h.liveActivity.latest?.isPaused == true)
        first.reset()
        paused.reset()
    }

    @Test("Una fase vencida al reabrir elimina la actividad antigua")
    func restoreExpired() {
        let h = Harness()
        let first = h.makeEngine()
        first.start()
        h.clock.advance(26 * 60)
        let restored = h.makeEngine()
        #expect(restored.phase == .shortBreak)
        #expect(h.liveActivity.latest == nil)
        first.reset()
    }

    @Test("Los nombres largos se acotan y el cambio de tarea se publica")
    func taskUpdate() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        engine.setTask(String(repeating: "á", count: 1000))
        #expect(h.liveActivity.latest?.task.count == 120)
        engine.reset()
    }

    @Test("El estado compartido se codifica sin perder fechas ni pausa")
    func coding() throws {
        let h = Harness(work: 90)
        let engine = h.makeEngine()
        engine.start()
        engine.pause()
        let state = try #require(h.liveActivity.latest)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(TimerActivityState.self, from: data) == state)
        #expect(state.pausedTime == "1:30:00")
        #expect(data.count < 4096)
        engine.reset()
    }
}

@MainActor
private final class FakeActivityBackend: LiveActivityBackend {
    var activityIDs: [String] = []
    var canStart = true
    var requests = 0
    var shouldFail = false
    var updates: [TimerActivityState] = []
    var ended: [String] = []
    enum Failure: Error { case unavailable }

    func request(_ state: TimerActivityState) throws {
        requests += 1
        if shouldFail { throw Failure.unavailable }
        activityIDs.append("activity-\(requests)")
    }
    func update(_ id: String, state: TimerActivityState) async {
        await Task.yield()
        updates.append(state)
    }
    func end(_ id: String) async {
        await Task.yield()
        ended.append(id)
        activityIDs.removeAll { $0 == id }
    }
}

@MainActor
@Suite("Ciclo de vida de ActivityKit")
struct LiveActivityControllerTests {
    private var state: TimerActivityState {
        TimerActivityState(phaseTitle: "Concentración", symbol: "timer", isBreak: false,
                           task: "", timerStart: Date(timeIntervalSince1970: 0),
                           endDate: Date(timeIntervalSince1970: 1500), remaining: 0)
    }

    @Test("Reutiliza la actividad recuperada y limpia duplicados")
    func adoption() async {
        let backend = FakeActivityBackend()
        backend.activityIDs = ["existing", "duplicate"]
        let controller = LiveActivityController(backend: backend)
        controller.synchronize(state)
        await controller.waitForUpdates()
        #expect(backend.requests == 0)
        #expect(backend.activityIDs == ["existing"])
        #expect(backend.updates == [state])
        #expect(backend.ended == ["duplicate"])
    }

    @Test("Ordena pausa, reanudación y fin aunque las actualizaciones sean asíncronas")
    func ordering() async {
        let backend = FakeActivityBackend()
        let controller = LiveActivityController(backend: backend)
        var paused = state
        paused.endDate = nil
        paused.timerStart = nil
        paused.remaining = 500
        controller.synchronize(state)
        controller.synchronize(paused)
        controller.synchronize(state)
        controller.synchronize(nil)
        await controller.waitForUpdates()
        #expect(backend.requests == 1)
        #expect(backend.updates == [paused, state])
        #expect(backend.activityIDs.isEmpty)
    }

    @Test("Sin permiso o en segundo plano no solicita; al volver puede reintentar")
    func unavailable() async {
        let backend = FakeActivityBackend()
        backend.canStart = false
        let controller = LiveActivityController(backend: backend)
        controller.synchronize(state)
        await controller.waitForUpdates()
        #expect(backend.requests == 0)
        backend.canStart = true
        controller.synchronize(state)
        await controller.waitForUpdates()
        #expect(backend.requests == 1)
    }

    @Test("Un fallo al crear no impide volver a intentarlo")
    func requestFailure() async {
        let backend = FakeActivityBackend()
        backend.shouldFail = true
        let controller = LiveActivityController(backend: backend)
        controller.synchronize(state)
        await controller.waitForUpdates()
        #expect(backend.activityIDs.isEmpty)
        backend.shouldFail = false
        controller.synchronize(state)
        await controller.waitForUpdates()
        #expect(backend.activityIDs.count == 1)
    }
}
