import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(IOKit)
import IOKit.pwr_mgt
#endif

/// Vibraciones que emite el motor, nombradas por lo que significan y no por su
/// intensidad, para que el motor no tenga que saber nada de UIKit.
enum HapticCue {
    case start
    case stop
    case skip
    case phaseComplete
}

/// Todo lo que el motor del ciclo provoca fuera de sí mismo: notificaciones,
/// sonido, vibración y pantalla encendida.
///
/// Existe para que `PomodoroEngine` sea lógica pura y comprobable: en la app se
/// usa `SystemEffects`, y en los tests un doble que solo apunta lo que recibe.
@MainActor
protocol PomodoroEffects {
    func scheduleEnd(for phase: PomodoroPhase, at date: Date)
    func cancelScheduledEnd()
    func playChime(_ kind: ChimeKind)
    /// Baja el sonido de fondo antes de la campana de fin de fase.
    func fadeOutAmbience()
    /// Pone el fondo sonoro de la fase que empieza. Lo hace el motor y no la
    /// vista, para que el cambio ocurra también con la ventana cerrada.
    func applyAmbience(_ config: SoundConfig)
    func haptic(_ cue: HapticCue)
    func setIdleTimerDisabled(_ disabled: Bool)
}

/// Implementación real, conectada a los servicios del sistema.
@MainActor
struct SystemEffects: PomodoroEffects {
    func scheduleEnd(for phase: PomodoroPhase, at date: Date) {
        NotificationScheduler.shared.scheduleEnd(for: phase, at: date)
    }

    func cancelScheduledEnd() {
        NotificationScheduler.shared.cancelAll()
    }

    func playChime(_ kind: ChimeKind) {
        AudioService.shared.playChime(kind)
    }

    func fadeOutAmbience() {
        AudioService.shared.fadeOutForPhaseChange()
    }

    func applyAmbience(_ config: SoundConfig) {
        AudioService.shared.apply(config)
    }

    func haptic(_ cue: HapticCue) {
        switch cue {
        case .start: Haptics.impact(.medium)
        case .stop: Haptics.impact(.light)
        case .skip: Haptics.impact(.rigid)
        case .phaseComplete: Haptics.notify(.success)
        }
    }

    #if canImport(UIKit)
    func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
    #else
    /// En el Mac se mantiene la pantalla encendida con una aserción de energía,
    /// que el sistema libera sola si la app termina.
    func setIdleTimerDisabled(_ disabled: Bool) {
        if disabled {
            guard SleepAssertion.id == IOPMAssertionID(kIOPMNullAssertionID) else { return }
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Pommodoro: bloque de concentración en marcha" as CFString,
                &SleepAssertion.id
            )
        } else if SleepAssertion.id != IOPMAssertionID(kIOPMNullAssertionID) {
            IOPMAssertionRelease(SleepAssertion.id)
            SleepAssertion.id = IOPMAssertionID(kIOPMNullAssertionID)
        }
    }
    #endif
}

#if !canImport(UIKit)
@MainActor
private enum SleepAssertion {
    static var id = IOPMAssertionID(kIOPMNullAssertionID)
}
#endif
