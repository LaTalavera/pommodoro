import SwiftData
import SwiftUI

/// El historial. Deliberadamente sobrio: sin rachas ni medallas, que castigan
/// el día malo, que es justo el día en que quieres que la persona vuelva.
struct HistorySheet: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar

    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    @State private var weekOffset = 0

    var body: some View {
        NavigationStack {
            Group {
                if workSessions.isEmpty {
                    empty
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            todayCard
                            weekSelector
                            weekCard
                            tasksCard
                            recentList
                        }
                        .padding(20)
                    }
                }
            }
            .background(Theme.base)
            .navigationTitle("Historial")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .tint(engine.phase.tint)
        .preferredColorScheme(.dark)
    }

    // MARK: - Datos

    private var workSessions: [Session] {
        sessions.filter { $0.phase == .work }
    }

    private var todaySummary: FocusHistorySummary {
        FocusHistorySummary(sessions: sessions, day: Date(), calendar: calendar)
    }

    private var selectedWeek: WeeklyFocusSummary {
        let date = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return WeeklyFocusSummary(sessions: sessions, containing: date, calendar: calendar)
    }

    private var weekRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM yyyy"
        let end = calendar.date(byAdding: .day, value: -1, to: selectedWeek.interval.end)!
        return "\(formatter.string(from: selectedWeek.interval.start)) – \(formatter.string(from: end))"
    }

    private var weekSelector: some View {
        HStack {
            Button { weekOffset -= 1 } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Semana anterior")
            Spacer(minLength: 4)
            VStack(spacing: 4) {
                Text(weekOffset == 0 ? "Esta semana" : "Resumen semanal")
                    .font(.headline)
                Text(weekRange).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("history.weekRange")
            }
            Spacer(minLength: 4)
            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Semana siguiente")
            .disabled(weekOffset >= 0)
        }
    }

    // MARK: - Piezas

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("Todavía no hay nada")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            Text("Cuando termines tu primer bloque aparecerá aquí.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var todayCard: some View {
        card(title: "Hoy") {
            HStack(alignment: .top, spacing: 0) {
                stat(
                    value: "\(todaySummary.completedBlocks)",
                    label: todaySummary.completedBlocks == 1 ? "bloque completado" : "bloques completados"
                )
                divider
                stat(value: focusedTimeToday, label: "concentrado")
                divider
                stat(
                    value: "\(todaySummary.interruptions)",
                    label: "interrupciones"
                )
            }
            Text("El tiempo concentrado incluye los bloques abandonados. Los descansos no cuentan.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var focusedTimeToday: String {
        FocusHistorySummary.durationLabel(seconds: todaySummary.focusedSeconds)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 38)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekCard: some View {
        let report = selectedWeek
        let maxSeconds = max(report.days.map { $0.summary.focusedSeconds }.max() ?? 0, 1)
        return card(title: "Tiempo de concentración") {
            HStack(alignment: .top, spacing: 0) {
                stat(value: FocusHistorySummary.durationLabel(seconds: report.summary.focusedSeconds), label: "concentrado")
                divider
                stat(value: "\(report.summary.completedBlocks)", label: "bloques completados")
                divider
                stat(value: "\(report.summary.interruptions)", label: "interrupciones")
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(report.days) { day in
                    let seconds = day.summary.focusedSeconds
                    VStack(spacing: 7) {
                        Text(seconds == 0 ? " " : (seconds < 60 ? "<1" : "\(Int(seconds / 60))"))
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(seconds == 0 ? Color.white.opacity(0.08) : PomodoroPhase.work.tint.opacity(0.85))
                            .frame(height: max(6, 74 * CGFloat(seconds / maxSeconds)))
                        Text(weekdayLabel(day.date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(calendar.isDateInToday(day.date) ? .white : .gray)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(FocusHistorySummary.durationLabel(seconds: seconds))
                }
            }
            .frame(height: 118, alignment: .bottom)
            Text("Minutos por día, incluidos los bloques abandonados. Cada sesión se cuenta en su fecha de inicio.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var tasksCard: some View {
        let report = selectedWeek
        return card(title: "Por tarea") {
            if report.tasks.isEmpty {
                Text("No hay sesiones de concentración esta semana.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("history.emptyWeek")
            } else {
                ForEach(report.tasks) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(task.title).font(.headline).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(FocusHistorySummary.durationLabel(seconds: task.summary.focusedSeconds))
                                .font(.subheadline.monospacedDigit())
                        }
                        ProgressView(value: task.summary.focusedSeconds,
                                     total: max(report.summary.focusedSeconds, 1))
                            .tint(PomodoroPhase.work.tint)
                            .accessibilityHidden(true)
                        Text("\(task.summary.completedBlocks) \(task.summary.completedBlocks == 1 ? "bloque completado" : "bloques completados") · \(task.summary.interruptions) \(task.summary.interruptions == 1 ? "interrupción" : "interrupciones")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(task.summary.externalInterruptions) \(task.summary.externalInterruptions == 1 ? "externa" : "externas") · \(task.summary.internalInterruptions) \(task.summary.internalInterruptions == 1 ? "propia" : "propias")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("history.task.\(task.id)")
                }
            }
        }
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date).uppercased()
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sesiones de la semana")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .kerning(1)

            ForEach(selectedWeek.sessions.prefix(40)) { session in
                row(session)
            }
        }
    }

    private func row(_ session: Session) -> some View {
        let abandoned = session.outcome == .abandoned
        return HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 2)
                .fill(abandoned ? Color.white.opacity(0.22) : PomodoroPhase.work.tint)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.task ?? "Sin tarea")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(session.task == nil ? .white.opacity(0.5) : .white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(timeLabel(session.startedAt))
                    Text("·")
                    Text(FocusHistorySummary.durationLabel(seconds: session.actualSeconds))
                    if abandoned {
                        Text("·")
                        Text("abandonado")
                    }
                    if session.totalInterruptions > 0 {
                        Text("·")
                        Label("\(session.totalInterruptions)", systemImage: "hand.raised")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        }
        .accessibilityElement(children: .combine)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    private func card<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .kerning(1)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                }
        }
    }
}
