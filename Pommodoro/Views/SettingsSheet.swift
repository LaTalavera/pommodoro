import SwiftUI

struct SettingsSheet: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @Bindable private var settings = AppSettings.shared

    /// Combinaciones habituales, para no tener que tocar tres steppers.
    private static let presets: [(name: String, work: Int, short: Int, long: Int)] = [
        ("Clásico", 25, 5, 15),
        ("Largo", 50, 10, 20),
        ("Profundo", 90, 20, 30),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        ForEach(Self.presets, id: \.name) { preset in
                            presetButton(preset)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                } header: {
                    Text("Ajustes rápidos")
                }

                Section {
                    minuteRow("Concentración", value: $settings.workMinutes, range: 1...120, tint: PomodoroPhase.work.tint)
                    minuteRow("Descanso corto", value: $settings.shortBreakMinutes, range: 1...60, tint: PomodoroPhase.shortBreak.tint)
                    minuteRow("Descanso largo", value: $settings.longBreakMinutes, range: 1...60, tint: PomodoroPhase.longBreak.tint)

                    Stepper(value: $settings.sessionsBeforeLongBreak, in: 2...8) {
                        LabeledContent("Bloques por ciclo", value: "\(settings.sessionsBeforeLongBreak)")
                    }
                } header: {
                    Text("Duraciones")
                } footer: {
                    Text("Tras \(settings.sessionsBeforeLongBreak) bloques de concentración llega el descanso largo. También puedes arrastrar sobre el anillo de la pantalla principal para fijar la duración de la fase actual.")
                }

                Section {
                    Picker("Medir en", selection: $settings.dailyGoalMode) {
                        ForEach(DailyGoalMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("goal.mode")
                    switch settings.dailyGoalMode {
                    case .blocks:
                        Stepper(value: $settings.dailyGoal, in: 1...20) {
                            LabeledContent("Meta diaria", value: "\(settings.dailyGoal) bloques")
                        }
                        .accessibilityIdentifier("goal.blocks")
                    case .minutes:
                        Stepper(value: $settings.dailyGoalMinutes, in: 5...600, step: 5) {
                            LabeledContent("Meta diaria", value: "\(settings.dailyGoalMinutes) min")
                        }
                        .accessibilityIdentifier("goal.minutes")
                    case .disabled:
                        Text("Puedes concentrarte sin una meta diaria.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Objetivo diario")
                } footer: {
                    Text("Los minutos incluyen el trabajo en curso y los bloques abandonados, sin pausas ni descansos. Cambiar la meta no interrumpe la sesión.")
                }

                Section("Encadenado") {
                    Toggle("Empezar el descanso solo", isOn: $settings.autoStartBreaks)
                    Toggle("Volver al trabajo solo", isOn: $settings.autoStartWork)
                }

                Section {
                    Picker("Ocultar los controles", selection: $settings.immersionMode) {
                        ForEach(ImmersionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Toggle("Mantener la pantalla encendida", isOn: $settings.keepScreenAwake)
                    Toggle("Campana al cambiar de fase", isOn: $settings.chimeEnabled)
                    Toggle("Vibración", isOn: $settings.hapticsEnabled)
                } header: {
                    Text("Durante la sesión")
                } footer: {
                    Text("Con el reloj en marcha los controles se retiran para dejar solo la cuenta atrás. Desliza hacia arriba para que ocurra al momento, o toca la pantalla para recuperarlos.")
                }

                Section {
                    Toggle("Recordar activar Concentración", isOn: focusToggleBinding)
                } footer: {
                    Text("iOS no deja que ninguna app encienda un modo de Concentración por ti. Esto solo detecta si ya tienes uno puesto y te avisa, sin sonido, si empiezas un bloque sin él.")
                }

                Section {
                    Button {
                        AudioService.shared.playChime(.workStart)
                    } label: {
                        Label("Probar la campana", systemImage: "bell")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.base)
            .navigationTitle("Ajustes")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .tint(engine.phase.tint)
        .onChange(of: settings.workMinutes) { _, _ in engine.settingsDidChange() }
        .onChange(of: settings.shortBreakMinutes) { _, _ in engine.settingsDidChange() }
        .onChange(of: settings.longBreakMinutes) { _, _ in engine.settingsDidChange() }
    }

    /// Al activarlo pide permiso de lectura de Concentración; si el usuario lo
    /// deniega, el ajuste vuelve a apagarse solo en vez de quedarse encendido
    /// sin poder hacer nada.
    private var focusToggleBinding: Binding<Bool> {
        Binding(
            get: { settings.suggestFocusMode },
            set: { newValue in
                settings.suggestFocusMode = newValue
                if newValue { FocusStatusMonitor.shared.requestAuthorization() }
            }
        )
    }

    private func minuteRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, tint: Color) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) min")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func presetButton(_ preset: (name: String, work: Int, short: Int, long: Int)) -> some View {
        let isActive = settings.workMinutes == preset.work
            && settings.shortBreakMinutes == preset.short
            && settings.longBreakMinutes == preset.long

        return Button {
            withAnimation(.snappy) {
                settings.workMinutes = preset.work
                settings.shortBreakMinutes = preset.short
                settings.longBreakMinutes = preset.long
            }
            Haptics.impact(.light)
        } label: {
            VStack(spacing: 3) {
                Text(preset.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("\(preset.work)/\(preset.short)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? engine.phase.tint.opacity(0.22) : Theme.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isActive ? engine.phase.tint.opacity(0.7) : Theme.stroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}
