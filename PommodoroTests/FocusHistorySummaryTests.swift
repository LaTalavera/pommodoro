import Foundation
import Testing
@testable import Pommodoro

@MainActor
@Suite("Historial fiel al esfuerzo")
struct FocusHistorySummaryTests {
    @Test("Las fracciones de minuto no se presentan como cero")
    func durationLabels() {
        #expect(FocusHistorySummary.durationLabel(seconds: 0) == "0 min")
        #expect(FocusHistorySummary.durationLabel(seconds: 32) == "< 1 min")
        #expect(FocusHistorySummary.durationLabel(seconds: 60) == "1 min")
        #expect(FocusHistorySummary.durationLabel(seconds: 1860) == "31 min")
        #expect(FocusHistorySummary.durationLabel(seconds: 3660) == "1 h 1 min")
    }

    private let day = Date(timeIntervalSince1970: 1_699_953_200)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func session(_ seconds: Double, outcome: SessionOutcome = .completed,
                         phase: PomodoroPhase = .work, date: Date? = nil) -> Session {
        Session(startedAt: date ?? day, endedAt: (date ?? day).addingTimeInterval(seconds),
                phase: phase, outcome: outcome, plannedSeconds: 1500, actualSeconds: seconds,
                task: nil, externalInterruptions: 1, internalInterruptions: 2)
    }

    @Test("Suma bloques completos y abandonados sin contar descansos ni otros días")
    func mixedEffort() {
        let summary = FocusHistorySummary(sessions: [
            session(1500), session(360, outcome: .abandoned),
            session(300, phase: .shortBreak), session(900, phase: .longBreak),
            session(1500, date: day.addingTimeInterval(-86400))
        ], day: day, calendar: calendar)
        #expect(summary.focusedSeconds == 1860)
        #expect(summary.abandonedSeconds == 360)
        #expect(summary.completedBlocks == 1)
        #expect(summary.interruptions == 6)
    }

    @Test("Un día con solo abandonos conserva todo el esfuerzo")
    func abandonedOnly() {
        let summary = FocusHistorySummary(sessions: [session(45, outcome: .abandoned)],
                                          day: day, calendar: calendar)
        #expect(summary.focusedSeconds == 45)
        #expect(summary.completedBlocks == 0)
    }

    @Test("Sin sesiones, todos los totales son cero")
    func empty() {
        let summary = FocusHistorySummary(sessions: [], day: day, calendar: calendar)
        #expect(summary.focusedSeconds == 0)
        #expect(summary.abandonedSeconds == 0)
        #expect(summary.completedBlocks == 0)
        #expect(summary.interruptions == 0)
    }

    @Test("El día se calcula con el calendario del usuario")
    func localDay() {
        var local = calendar
        local.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        let midnightUTC = calendar.startOfDay(for: day)
        let summary = FocusHistorySummary(sessions: [
            session(120, outcome: .abandoned, date: midnightUTC.addingTimeInterval(-3600)),
            session(600, date: midnightUTC.addingTimeInterval(-3 * 3600))
        ], day: midnightUTC, calendar: local)
        #expect(summary.focusedSeconds == 120)
        #expect(summary.completedBlocks == 0)
    }

    @Test("Al abandonar tras una pausa solo cuenta el tiempo trabajado")
    func pausedAbandonment() throws {
        let h = Harness()
        let engine = h.makeEngine()
        engine.start()
        h.clock.advance(120)
        engine.pause()
        h.clock.advance(600)
        engine.start()
        h.clock.advance(60)
        engine.skip()
        let record = try #require(h.recorder.workRecords.first)
        #expect(record.actualSeconds == 180)
        let summary = FocusHistorySummary(sessions: [
            session(record.actualSeconds, outcome: record.outcome, date: record.startedAt)
        ], day: h.clock.now, calendar: h.calendar)
        #expect(summary.focusedSeconds == 180)
        #expect(summary.abandonedSeconds == 180)
        #expect(summary.completedBlocks == 0)
    }
}
