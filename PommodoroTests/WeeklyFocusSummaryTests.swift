import Foundation
import Testing
@testable import Pommodoro

@MainActor
@Suite("Resúmenes por semana y tarea")
struct WeeklyFocusSummaryTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Madrid")!
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func session(_ date: Date, seconds: Double, task: String? = "Leer",
                         phase: PomodoroPhase = .work, outcome: SessionOutcome = .completed) -> Session {
        Session(startedAt: date, endedAt: date.addingTimeInterval(seconds), phase: phase,
                outcome: outcome, plannedSeconds: 1500, actualSeconds: seconds, task: task,
                externalInterruptions: 1, internalInterruptions: 2)
    }

    @Test("La semana incluye lunes y domingo y excluye el lunes siguiente")
    func boundaries() {
        let report = WeeklyFocusSummary(sessions: [
            session(date(2026, 9, 14, hour: 0), seconds: 1500),
            session(date(2026, 9, 20, hour: 23), seconds: 300, outcome: .abandoned),
            session(date(2026, 9, 21, hour: 0), seconds: 600),
            session(date(2026, 9, 13), seconds: 600),
            session(date(2026, 9, 18), seconds: 600, phase: .shortBreak)
        ], containing: date(2026, 9, 18), calendar: calendar)
        #expect(report.summary.focusedSeconds == 1800)
        #expect(report.summary.completedBlocks == 1)
        #expect(report.summary.interruptions == 6)
        #expect(report.days.count == 7)
        #expect(report.days.first?.summary.focusedSeconds == 1500)
        #expect(report.days.last?.summary.focusedSeconds == 300)
        #expect(report.days.reduce(0) { $0 + $1.summary.focusedSeconds } == report.summary.focusedSeconds)
    }

    @Test("Agrupa nombres sin distinguir mayúsculas ni espacios sobrantes")
    func taskGrouping() {
        let report = WeeklyFocusSummary(sessions: [
            session(date(2026, 9, 14), seconds: 900, task: " Leer  Swift "),
            session(date(2026, 9, 15), seconds: 600, task: "leer\nSwift", outcome: .abandoned),
            session(date(2026, 9, 16), seconds: 300, task: "Escribir")
        ], containing: date(2026, 9, 18), calendar: calendar)
        #expect(report.tasks.count == 2)
        #expect(report.tasks[0].summary.focusedSeconds == 1500)
        #expect(report.tasks[0].summary.completedBlocks == 1)
        #expect(report.tasks[0].summary.externalInterruptions == 2)
        #expect(report.tasks[0].summary.internalInterruptions == 4)
        #expect(report.tasks.reduce(0) { $0 + $1.summary.focusedSeconds } == report.summary.focusedSeconds)
    }

    @Test("Las sesiones sin tarea tienen su propio grupo, incluso si hay una tarea llamada Sin tarea")
    func unassigned() {
        let report = WeeklyFocusSummary(sessions: [
            session(date(2026, 9, 14), seconds: 90, task: nil),
            session(date(2026, 9, 15), seconds: 60, task: "  "),
            session(date(2026, 9, 16), seconds: 30, task: "Sin tarea")
        ], containing: date(2026, 9, 18), calendar: calendar)
        #expect(report.tasks.count == 2)
        #expect(report.tasks.first?.id == "untitled")
        #expect(report.tasks.first?.summary.focusedSeconds == 150)
    }

    @Test("Una semana vacía conserva los siete días y totales cero")
    func emptyWeek() {
        let report = WeeklyFocusSummary(sessions: [], containing: date(2026, 9, 18), calendar: calendar)
        #expect(report.days.count == 7)
        #expect(report.tasks.isEmpty)
        #expect(report.summary.focusedSeconds == 0)
    }

    @Test("La semana con cambio de hora tiene siete días locales, no 168 horas fijas")
    func daylightSaving() {
        let report = WeeklyFocusSummary(sessions: [
            session(date(2026, 3, 29, hour: 23), seconds: 600),
            session(date(2026, 3, 30, hour: 0), seconds: 300)
        ], containing: date(2026, 3, 29), calendar: calendar)
        #expect(report.interval.duration == 167 * 3600)
        #expect(report.summary.focusedSeconds == 600)
        #expect(report.days.count == 7)
    }

    @Test("La semana de fin de año conserva sus sesiones de ambos años")
    func yearBoundary() {
        let report = WeeklyFocusSummary(sessions: [
            session(date(2025, 12, 31), seconds: 600),
            session(date(2026, 1, 1), seconds: 900)
        ], containing: date(2026, 1, 1), calendar: calendar)
        #expect(report.summary.focusedSeconds == 1500)
        #expect(report.days.first?.date == date(2025, 12, 29, hour: 0))
    }
}
