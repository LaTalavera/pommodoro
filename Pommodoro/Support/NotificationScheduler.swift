import Foundation
import UserNotifications

/// Avisa del fin de la fase aunque la app esté en segundo plano o la pantalla
/// bloqueada. La cuenta atrás en sí no depende de esto: se recalcula contra el
/// reloj del sistema al volver.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false

    private init() {}

    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleEnd(for phase: PomodoroPhase, at date: Date) {
        requestAuthorizationIfNeeded()
        cancelAll()

        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        switch phase {
        case .work:
            content.title = "Bloque completado"
            content.body = "Tómate un descanso."
        case .shortBreak, .longBreak:
            content.title = "Descanso terminado"
            content.body = "Vuelve a la tarea cuando quieras."
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    private static let identifier = "com.pommodoro.phase-end"
}
