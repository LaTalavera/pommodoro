import Foundation

/// Las semanas respetan el calendario local. Como el historial diario, cada
/// sesión pertenece al día en que empezó, aunque termine después de medianoche.
struct WeeklyFocusSummary {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let summary: FocusHistorySummary
    }

    struct Task: Identifiable {
        let id: String
        let title: String
        let summary: FocusHistorySummary
    }

    let interval: DateInterval
    let summary: FocusHistorySummary
    let days: [Day]
    let tasks: [Task]
    let sessions: [Session]

    init(sessions: [Session], containing date: Date, calendar: Calendar) {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        interval = DateInterval(start: start, end: end)
        let work = sessions.filter {
            $0.phase == .work && $0.startedAt >= start && $0.startedAt < end
        }.sorted { $0.startedAt > $1.startedAt }
        self.sessions = work
        summary = FocusHistorySummary(sessions: work)
        days = (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return Day(date: day, summary: FocusHistorySummary(sessions: work, day: day, calendar: calendar))
        }
        let groups = Dictionary(grouping: work) { session in
            let name = Self.taskName(session.task)
            return name.isEmpty ? "untitled" : "task:" + name.lowercased()
        }
        tasks = groups.map { key, rows in
            let name = Self.taskName(rows.first?.task)
            return Task(id: key, title: name.isEmpty ? "Sin tarea" : name,
                        summary: FocusHistorySummary(sessions: rows))
        }.sorted {
            if $0.summary.focusedSeconds != $1.summary.focusedSeconds {
                return $0.summary.focusedSeconds > $1.summary.focusedSeconds
            }
            return $0.id < $1.id
        }
    }

    private static func taskName(_ name: String?) -> String {
        (name ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
