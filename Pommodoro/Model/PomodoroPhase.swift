import SwiftUI

/// Las tres fases del ciclo Pomodoro.
enum PomodoroPhase: String, CaseIterable, Codable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: "Concentración"
        case .shortBreak: "Descanso"
        case .longBreak: "Descanso largo"
        }
    }

    var symbol: String {
        switch self {
        case .work: "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "figure.walk"
        }
    }

    var isBreak: Bool { self != .work }

    /// Color de acento de la fase. Todo el tema visual cuelga de aquí.
    var tint: Color {
        switch self {
        case .work: Color(red: 0.98, green: 0.44, blue: 0.36)
        case .shortBreak: Color(red: 0.34, green: 0.84, blue: 0.72)
        case .longBreak: Color(red: 0.51, green: 0.60, blue: 0.98)
        }
    }
}
