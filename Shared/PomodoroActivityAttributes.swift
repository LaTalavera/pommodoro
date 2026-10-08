import Foundation

#if os(iOS)
import ActivityKit
private typealias ActivityAttributesBase = ActivityAttributes
#else
/// ActivityKit no existe en macOS; el motor sigue compartiendo el mismo estado.
private protocol ActivityAttributesBase {
    associatedtype ContentState: Codable & Hashable
}
#endif

struct PomodoroActivityAttributes: ActivityAttributesBase {
    struct ContentState: Codable, Hashable {
        var phaseTitle: String
        var symbol: String
        var isBreak: Bool
        var task: String
        /// A fixed range lets the system render the countdown while the app sleeps.
        var timerStart: Date?
        var endDate: Date?
        var remaining: TimeInterval

        var isPaused: Bool { endDate == nil }
        var timerInterval: ClosedRange<Date>? {
            guard let timerStart, let endDate else { return nil }
            return min(timerStart, endDate)...endDate
        }

        var pausedTime: String {
            let seconds = Int(ceil(max(remaining, 0)))
            if seconds >= 3600 {
                return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            }
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
    }
}
