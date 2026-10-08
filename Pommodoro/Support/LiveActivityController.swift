import OSLog
#if canImport(UIKit)
import ActivityKit
import UIKit
#endif

typealias TimerActivityState = PomodoroActivityAttributes.ContentState

@MainActor
protocol LiveActivityManaging {
    func synchronize(_ state: TimerActivityState?)
}

/// Small boundary around ActivityKit so lifecycle and ordering can be tested.
@MainActor
protocol LiveActivityBackend {
    var activityIDs: [String] { get }
    var canStart: Bool { get }
    func request(_ state: TimerActivityState) throws
    func update(_ id: String, state: TimerActivityState) async
    func end(_ id: String) async
}

@MainActor
final class LiveActivityController: LiveActivityManaging {
    static let shared = LiveActivityController(backend: PlatformLiveActivityBackend())
    private let backend: LiveActivityBackend
    private var pending: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.pommodoro.app", category: "LiveActivity")

    init(backend: LiveActivityBackend) { self.backend = backend }

    func synchronize(_ state: TimerActivityState?) {
        // Serialize transitions: a slow pause update must not overwrite resume.
        let previous = pending
        pending = Task { @MainActor [self] in
            await previous?.value
            let ids = backend.activityIDs
            guard let state else {
                for id in ids { await backend.end(id) }
                return
            }
            if let id = ids.first {
                await backend.update(id, state: state)
                for duplicate in ids.dropFirst() { await backend.end(duplicate) }
            } else if backend.canStart {
                do {
                    try backend.request(state)
                } catch {
                    logger.error("No se pudo iniciar la actividad: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func waitForUpdates() async { await pending?.value }
}

#if canImport(UIKit)
@MainActor
private struct PlatformLiveActivityBackend: LiveActivityBackend {
    private var activities: [Activity<PomodoroActivityAttributes>] {
        Activity<PomodoroActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    var activityIDs: [String] { activities.map(\.id) }
    var canStart: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
            && UIApplication.shared.applicationState == .active
    }

    func request(_ state: TimerActivityState) throws {
        _ = try Activity.request(
            attributes: PomodoroActivityAttributes(),
            content: ActivityContent(state: state, staleDate: state.endDate),
            pushType: nil
        )
    }

    func update(_ id: String, state: TimerActivityState) async {
        await activities.first { $0.id == id }?.update(
            ActivityContent(state: state, staleDate: state.endDate)
        )
    }

    func end(_ id: String) async {
        await activities.first { $0.id == id }?.end(nil, dismissalPolicy: .immediate)
    }
}
#else
/// El Mac no inicia Live Activities propias; las del iPhone se reflejan solas
/// en su barra de menús.
@MainActor
private struct PlatformLiveActivityBackend: LiveActivityBackend {
    var activityIDs: [String] { [] }
    var canStart: Bool { false }
    func request(_ state: TimerActivityState) throws {}
    func update(_ id: String, state: TimerActivityState) async {}
    func end(_ id: String) async {}
}
#endif
