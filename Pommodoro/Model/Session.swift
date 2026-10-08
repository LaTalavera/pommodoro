import Foundation
import SwiftData

/// Cómo terminó un bloque. La distinción es el dato más accionable de la app:
/// saber en qué bloques te caíste, y a qué hora, dice más que el total.
enum SessionOutcome: String, Codable, CaseIterable {
    case completed
    case abandoned

    var title: String {
        switch self {
        case .completed: "Completado"
        case .abandoned: "Abandonado"
        }
    }
}

/// Una sesión ya terminada, tal como se guarda.
@Model
final class Session {
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var phaseRaw: String = PomodoroPhase.work.rawValue
    var outcomeRaw: String = SessionOutcome.completed.rawValue
    /// Lo que duraba la fase configurada.
    var plannedSeconds: Double = 0
    /// Lo que duró de verdad. Difiere de `plannedSeconds` si se abandonó.
    var actualSeconds: Double = 0
    var task: String?
    /// Interrupciones venidas de fuera (alguien te habla, suena el teléfono).
    var externalInterruptions: Int = 0
    /// Distracciones propias (te vas tú a mirar otra cosa).
    var internalInterruptions: Int = 0

    init(
        startedAt: Date,
        endedAt: Date,
        phase: PomodoroPhase,
        outcome: SessionOutcome,
        plannedSeconds: Double,
        actualSeconds: Double,
        task: String?,
        externalInterruptions: Int,
        internalInterruptions: Int
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phaseRaw = phase.rawValue
        self.outcomeRaw = outcome.rawValue
        self.plannedSeconds = plannedSeconds
        self.actualSeconds = actualSeconds
        self.task = task
        self.externalInterruptions = externalInterruptions
        self.internalInterruptions = internalInterruptions
    }

    var phase: PomodoroPhase { PomodoroPhase(rawValue: phaseRaw) ?? .work }
    var outcome: SessionOutcome { SessionOutcome(rawValue: outcomeRaw) ?? .completed }
    var totalInterruptions: Int { externalInterruptions + internalInterruptions }
}

/// Lo que el motor entrega cuando una fase termina. Es un valor sin dependencia
/// de SwiftData, para que el motor siga siendo comprobable sin base de datos.
struct SessionRecord: Equatable {
    var startedAt: Date
    var endedAt: Date
    var phase: PomodoroPhase
    var outcome: SessionOutcome
    var plannedSeconds: Double
    var actualSeconds: Double
    var task: String?
    var externalInterruptions: Int
    var internalInterruptions: Int
}

@MainActor
protocol SessionRecording {
    func record(_ record: SessionRecord)
    /// Tareas recientes, para no tener que teclear lo mismo cinco veces al día.
    func recentTasks(limit: Int) -> [String]
}

/// Implementación real sobre SwiftData.
@MainActor
struct SwiftDataSessionRecorder: SessionRecording {
    let context: ModelContext

    func record(_ record: SessionRecord) {
        context.insert(
            Session(
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                phase: record.phase,
                outcome: record.outcome,
                plannedSeconds: record.plannedSeconds,
                actualSeconds: record.actualSeconds,
                task: record.task,
                externalInterruptions: record.externalInterruptions,
                internalInterruptions: record.internalInterruptions
            )
        )
        try? context.save()
    }

    func recentTasks(limit: Int) -> [String] {
        var descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        guard let sessions = try? context.fetch(descriptor) else { return [] }

        var seen = Set<String>()
        var result: [String] = []
        for session in sessions {
            guard let task = session.task?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !task.isEmpty, seen.insert(task.lowercased()).inserted
            else { continue }
            result.append(task)
            if result.count == limit { break }
        }
        return result
    }
}
