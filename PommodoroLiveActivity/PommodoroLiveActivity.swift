import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PommodoroWidgets: WidgetBundle {
    var body: some Widget { PommodoroLiveActivity() }
}

struct PommodoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PomodoroActivityAttributes.self) { context in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(context.state.phaseTitle, systemImage: context.state.symbol)
                        .font(.headline)
                        .foregroundStyle(tint(context.state))
                    if !context.state.task.isEmpty {
                        Text(context.state.task).font(.subheadline).lineLimit(1)
                    }
                    Text(status(context)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Countdown(state: context.state)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .frame(maxWidth: 165)
                    .minimumScaleFactor(0.6)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.07, green: 0.08, blue: 0.12))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phaseTitle, systemImage: context.state.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(tint(context.state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .frame(width: 96, alignment: .trailing)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !context.state.task.isEmpty {
                            Text(context.state.task).lineLimit(1)
                        }
                        Text(status(context)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.state.symbol)
                    .foregroundStyle(tint(context.state))
            } compactTrailing: {
                Countdown(state: context.state).font(.caption.monospacedDigit()).frame(width: 62)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(tint(context.state))
            }
            .keylineTint(tint(context.state))
        }
    }

    private func tint(_ state: PomodoroActivityAttributes.ContentState) -> Color {
        state.isBreak ? .mint : .orange
    }

    private func status(_ context: ActivityViewContext<PomodoroActivityAttributes>) -> String {
        if context.state.isPaused { return "En pausa · Toca para continuar" }
        if context.isStale { return "Fase terminada · Abre Pommodoro" }
        return "En marcha"
    }
}

private struct Countdown: View {
    let state: PomodoroActivityAttributes.ContentState

    var body: some View {
        Group {
            if let interval = state.timerInterval {
                Text(timerInterval: interval, countsDown: true)
            } else {
                Text(state.pausedTime)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityHint(state.isPaused ? "Tiempo restante en pausa" : "Cuenta atrás")
    }
}
