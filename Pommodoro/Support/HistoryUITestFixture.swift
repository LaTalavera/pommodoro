#if DEBUG
import Foundation
import SwiftData

/// Datos reproducibles y exclusivamente en memoria para comprobar la interfaz.
@MainActor
enum HistoryUITestFixture {
    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let week = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
        let rows: [(Date, String?, Double, SessionOutcome)] = [
            (today.addingTimeInterval(9 * 3600), "Estudiar", 1500, .completed),
            (today.addingTimeInterval(10 * 3600), " Estudiar ", 300, .abandoned),
            (week.addingTimeInterval(3600), "Escribir", 600, .completed),
            (today.addingTimeInterval(11 * 3600), nil, 120, .abandoned),
            (previous.addingTimeInterval(3600), "Semana pasada", 900, .completed)
        ]
        for (date, task, seconds, outcome) in rows {
            context.insert(Session(startedAt: date, endedAt: date.addingTimeInterval(seconds),
                                   phase: .work, outcome: outcome, plannedSeconds: 1500,
                                   actualSeconds: seconds, task: task,
                                   externalInterruptions: 1, internalInterruptions: 2))
        }
        try! context.save()
    }
}
#endif
