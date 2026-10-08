import Foundation

/// Time worked is effort, even when a block wasn't completed. Keep completed
/// blocks separate, and exclude breaks from both effort and interruptions.
struct FocusHistorySummary {
    let completedBlocks: Int
    let focusedSeconds: TimeInterval
    let abandonedSeconds: TimeInterval
    let interruptions: Int
    let externalInterruptions: Int
    let internalInterruptions: Int

    init(sessions: [Session], day: Date, calendar: Calendar) {
        self.init(sessions: sessions.filter {
            $0.phase == .work && calendar.isDate($0.startedAt, inSameDayAs: day)
        })
    }

    init(sessions: [Session]) {
        let work = sessions.filter { $0.phase == .work }
        completedBlocks = work.filter { $0.outcome == .completed }.count
        focusedSeconds = work.reduce(0) { $0 + max(0, $1.actualSeconds) }
        abandonedSeconds = work.filter { $0.outcome == .abandoned }
            .reduce(0) { $0 + max(0, $1.actualSeconds) }
        interruptions = work.reduce(0) { $0 + $1.totalInterruptions }
        externalInterruptions = work.reduce(0) { $0 + $1.externalInterruptions }
        internalInterruptions = work.reduce(0) { $0 + $1.internalInterruptions }
    }

    static func durationLabel(seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "< 1 min" }
        let minutes = Int(max(0, seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
