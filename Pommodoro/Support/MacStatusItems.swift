#if os(macOS)
import AppKit
import Observation
import SwiftUI

/// Lo que se ve en la barra de menús: el icono de la fase y, con un bloque
/// empezado, la cuenta atrás. En el Mac hace el papel de la Live Activity.
struct MenuBarTimerLabel: View {
    let engine: PomodoroEngine

    var body: some View {
        if engine.runState == .idle {
            Image(systemName: "timer")
        } else {
            HStack(spacing: 4) {
                Image(systemName: engine.isRunning ? engine.phase.symbol : "pause.fill")
                Text(engine.remaining.clockString)
                    .monospacedDigit()
            }
        }
    }
}

/// El menú que se despliega desde la barra: controlar el temporizador sin
/// tener que traer la ventana.
struct MenuBarTimerMenu: View {
    let engine: PomodoroEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)

        Divider()

        Button(engine.isRunning ? "Pausar" : "Empezar") { engine.toggle() }
        Button("Saltar a la fase siguiente") { engine.skip() }
        Button("Reiniciar la fase") { engine.reset() }
            .disabled(engine.runState == .idle)

        Divider()

        Button("Abrir Pommodoro") {
            openWindow(id: PommodoroApp.timerWindowID)
            NSApp.activate()
        }
        SettingsLink {
            Text("Ajustes…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Salir de Pommodoro") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        let state = switch engine.runState {
        case .running: "en marcha"
        case .paused: "en pausa"
        case .idle: "lista"
        }
        return "\(engine.phase.title) · \(engine.remaining.clockString) · \(state)"
    }
}

/// Minutos restantes sobre el icono del Dock. Sigue al motor por su cuenta,
/// así funciona aunque la ventana esté cerrada.
@MainActor
final class DockBadge {
    private let engine: PomodoroEngine
    private var lastLabel: String?

    init(engine: PomodoroEngine) {
        self.engine = engine
        observe()
    }

    private func observe() {
        let label = withObservationTracking {
            Self.label(runState: engine.runState, remaining: engine.remaining)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        // El motor publica cinco veces por segundo; el Dock solo se toca
        // cuando cambia lo que se ve.
        guard label != lastLabel else { return }
        lastLabel = label
        NSApp?.dockTile.badgeLabel = label
    }

    /// Minutos que faltan, redondeando hacia arriba como el reloj: con 24:01
    /// en pantalla el Dock dice 25. El último minuto se cuenta en segundos.
    static func label(runState: PomodoroEngine.RunState, remaining: TimeInterval) -> String? {
        guard runState != .idle else { return nil }
        let seconds = Int(remaining.rounded(.up))
        return seconds < 60 ? "\(seconds)s" : "\((seconds + 59) / 60)"
    }
}
#endif
