import Intents
import Observation

/// Detecta si el usuario ya tiene un modo de Concentración activo.
///
/// iOS no da a las apps de terceros ninguna API para ENCENDER un modo de
/// Concentración — eso es privilegio exclusivo de la app Shortcuts, a través
/// de una acción privada. Lo único disponible públicamente es `INFocusStatusCenter`,
/// de solo lectura: sirve para recordar al usuario que lo active él mismo, no
/// para activarlo por él.
@MainActor
@Observable
final class FocusStatusMonitor {
    static let shared = FocusStatusMonitor()

    private(set) var isAuthorized = false
    private(set) var isFocused = false

    private var pollTask: Task<Void, Never>?

    private init() {
        isAuthorized = INFocusStatusCenter.default.authorizationStatus == .authorized
    }

    func requestAuthorization() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.isAuthorized = status == .authorized
                self?.refresh()
            }
        }
    }

    /// Sondea en vez de depender de una notificación de cambio: la app solo
    /// necesita saberlo mientras dura un bloque de trabajo, así que una
    /// comprobación cada pocos segundos es más que suficiente y evita atarse
    /// al nombre exacto de una notificación del sistema.
    func startPolling() {
        guard isAuthorized, pollTask == nil else { return }
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh() {
        isFocused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
    }
}
