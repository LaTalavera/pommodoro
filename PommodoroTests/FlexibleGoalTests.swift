import Foundation
import Testing
@testable import Pommodoro

@MainActor
@Suite("Objetivos flexibles")
struct FlexibleGoalTests {
    private let day = Date(timeIntervalSince1970: 1_700_006_400)
    private func progress(_ seconds: Double, mode: DailyGoalMode = .minutes,
                          minutes: Int = 60, day: Date? = nil) -> DailyGoal.Progress {
        DailyGoal.Progress(day: day ?? self.day, mode: mode, blocks: 4, minutes: minutes,
                           summary: FocusHistorySummary(sessions: []), activeSeconds: seconds)
    }

    @Test("Los minutos se alcanzan con segundos exactos, sin redondear antes de tiempo")
    func minuteThreshold() {
        #expect(!progress(3599.9).reached)
        #expect(progress(3600).reached)
        #expect(DailyGoal.shouldCelebrate(before: progress(3599), after: progress(3600), lastCelebrationDay: nil))
        #expect(progress(3600).label == "60/60 min hoy")
    }

    @Test("Los bloques no cuentan el tiempo de una sesión en curso")
    func blocksOnly() {
        #expect(!progress(10000, mode: .blocks).reached)
        #expect(progress(10000, mode: .blocks).value == 0)
    }

    @Test("Desactivar el objetivo no celebra aunque aumente el trabajo")
    func disabled() {
        #expect(!progress(10000, mode: .disabled).reached)
        #expect(!DailyGoal.shouldCelebrate(before: progress(0, mode: .disabled),
                                           after: progress(10000, mode: .disabled), lastCelebrationDay: nil))
    }

    @Test("Cambiar la meta, el modo o el día no produce una celebración artificial")
    func configurationChanges() {
        #expect(!DailyGoal.shouldCelebrate(before: progress(3000), after: progress(3000, minutes: 30), lastCelebrationDay: nil))
        #expect(!DailyGoal.shouldCelebrate(before: progress(3600, mode: .blocks), after: progress(3600), lastCelebrationDay: nil))
        #expect(!DailyGoal.shouldCelebrate(before: progress(0), after: progress(3600, day: day.addingTimeInterval(86400)), lastCelebrationDay: nil))
    }

    @Test("La celebración no se repite al guardar ni reabrir, y se permite al día siguiente")
    func oncePerDay() {
        #expect(!DailyGoal.shouldCelebrate(before: progress(3500), after: progress(3600), lastCelebrationDay: day))
        #expect(DailyGoal.shouldCelebrate(before: progress(3500), after: progress(3600), lastCelebrationDay: day.addingTimeInterval(-86400)))
    }

    @Test("Los minutos guardados de un abandono se suman al bloque en curso")
    func partialEffort() {
        let session = Session(startedAt: day, endedAt: day.addingTimeInterval(600), phase: .work,
                              outcome: .abandoned, plannedSeconds: 1500, actualSeconds: 600,
                              task: nil, externalInterruptions: 0, internalInterruptions: 0)
        let result = DailyGoal.Progress(day: day, mode: .minutes, blocks: 4, minutes: 15,
                                        summary: FocusHistorySummary(sessions: [session]), activeSeconds: 300)
        #expect(result.reached)
        #expect(result.value == 900)
    }

    @Test("Se conservan las preferencias existentes y cada modo guarda su meta")
    func preferencesAndMigration() {
        let suite = "goals.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.set(6, forKey: "dailyGoal")
        let settings = AppSettings(defaults: store)
        #expect(settings.dailyGoalMode == .blocks)
        #expect(settings.dailyGoal == 6)
        settings.dailyGoalMode = .minutes
        settings.dailyGoalMinutes = 95
        settings.lastGoalCelebrationDay = day
        let reloaded = AppSettings(defaults: store)
        #expect(reloaded.dailyGoalMode == .minutes)
        #expect(reloaded.dailyGoalMinutes == 95)
        #expect(reloaded.dailyGoal == 6)
        #expect(reloaded.lastGoalCelebrationDay == day)
        reloaded.dailyGoalMode = .disabled
        #expect(AppSettings(defaults: store).dailyGoalMode == .disabled)
    }

    @Test("Un objetivo antiguo de cero sigue desactivado tras migrar")
    func disabledMigration() {
        let suite = "goals.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.set(0, forKey: "dailyGoal")
        #expect(AppSettings(defaults: store).dailyGoalMode == .disabled)
    }

    @Test("El trabajo activo se congela en pausa y desaparece al guardarlo")
    func activeEffort() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(90)
        engine.pause()
        #expect(engine.currentDayWorkSeconds == 90)
        h.clock.advance(600)
        engine.sync()
        #expect(engine.currentDayWorkSeconds == 90)
        engine.start()
        h.clock.advance(30)
        engine.skip()
        #expect(engine.currentDayWorkSeconds == 0)
        #expect(h.recorder.workRecords.first?.actualSeconds == 120)
        engine.start()
        h.clock.advance(60)
        engine.sync()
        #expect(engine.currentDayWorkSeconds == 0, "El descanso no cuenta")
        engine.reset()
    }

    @Test("Cambiar ajustes no falsea el esfuerzo de una sesión activa ni pausada")
    func frozenDuration() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(120)
        h.settings.workMinutes = 50
        engine.settingsDidChange()
        engine.pause()
        #expect(engine.currentDayWorkSeconds == 120)
        #expect(engine.totalForPhase == 1500)
        engine.setCurrentPhaseDuration(minutes: 10)
        engine.settingsDidChange()
        #expect(engine.remaining == 1380)
        let restored = h.makeEngine()
        #expect(restored.currentDayWorkSeconds == 120)
        restored.reset()
        #expect(h.recorder.workRecords.first?.actualSeconds == 120)
        #expect(restored.remaining == 3000)
        engine.reset()
    }

    @Test("El trabajo iniciado ayer no aparece en el objetivo de hoy")
    func midnight() {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(60)
        engine.pause()
        h.clock.advance(86400)
        engine.sync()
        #expect(engine.currentDayWorkSeconds == 0)
        engine.reset()
    }
}
