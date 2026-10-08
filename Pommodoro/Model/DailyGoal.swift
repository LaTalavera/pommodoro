import Foundation

enum DailyGoalMode: String, CaseIterable, Identifiable {
    case blocks, minutes, disabled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blocks: "Bloques"
        case .minutes: "Minutos"
        case .disabled: "Sin objetivo"
        }
    }
}

/// Lógica pura del objetivo diario, separada de la vista para poder probarla
/// sin arrancar SwiftUI.
enum DailyGoal {
    struct Progress: Equatable {
        let day: Date
        let mode: DailyGoalMode
        let value: Double
        let target: Double

        init(day: Date, mode: DailyGoalMode, blocks: Int, minutes: Int,
             summary: FocusHistorySummary, activeSeconds: TimeInterval = 0) {
            self.day = day
            self.mode = mode
            switch mode {
            case .blocks:
                value = Double(summary.completedBlocks)
                target = Double(max(1, blocks))
            case .minutes:
                value = summary.focusedSeconds + max(0, activeSeconds)
                target = Double(max(1, minutes)) * 60
            case .disabled:
                value = Double(summary.completedBlocks)
                target = 0
            }
        }

        var reached: Bool { target > 0 && value >= target }
        var label: String {
            switch mode {
            case .blocks: "\(Int(value))/\(Int(target)) bloques hoy"
            case .minutes: "\(Int(value / 60))/\(Int(target / 60)) min hoy"
            case .disabled: "\(Int(value)) bloques hoy"
            }
        }

        var achievementText: String {
            mode == .minutes
                ? "\(FocusHistorySummary.durationLabel(seconds: value)) de concentración hoy. Es un buen momento para parar."
                : "\(Int(value)) \(value == 1 ? "bloque" : "bloques") de concentración hoy. Es un buen momento para parar."
        }
    }

    /// Cambiar el ajuste o de día no celebra nada. La marca persistida evita
    /// repetir la hoja al guardar el bloque en curso o al reabrir la aplicación.
    static func shouldCelebrate(before: Progress, after: Progress, lastCelebrationDay: Date?) -> Bool {
        before.day == after.day && before.mode == after.mode && before.target == after.target
            && lastCelebrationDay != after.day && !before.reached && after.reached
    }

    /// Si el recuento acaba de cruzar el objetivo con este último bloque.
    /// Se dispara una sola vez, justo al cruzar — no en cada bloque posterior.
    static func justReached(before: Int, after: Int, goal: Int) -> Bool {
        guard goal > 0 else { return false }
        return before < goal && after >= goal
    }
}
