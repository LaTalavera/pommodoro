import SwiftUI

/// Elegir en qué vas a trabajar antes de arrancar. Es la decisión que la
/// técnica pide de verdad; el contador solo la protege.
struct TaskSheet: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var recents: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextField("Escribe una tarea", text: $text)
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(commit)
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.card)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Theme.stroke, lineWidth: 1)
                                }
                        }

                    if !recents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recientes")
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                                .textCase(.uppercase)
                                .kerning(1)

                            ForEach(recents, id: \.self) { task in
                                Button {
                                    text = task
                                    commit()
                                } label: {
                                    HStack {
                                        Text(task)
                                            .font(.system(.body, design: .rounded))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .background {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Theme.card)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !engine.currentTask.isEmpty {
                        Button(role: .destructive) {
                            engine.setTask("")
                            dismiss()
                        } label: {
                            Label("Quitar la tarea", systemImage: "xmark.circle")
                                .font(.system(.subheadline, design: .rounded))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Theme.base)
            .navigationTitle("¿En qué trabajas?")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo", action: commit)
                }
            }
        }
        .tint(engine.phase.tint)
        .preferredColorScheme(.dark)
        .onAppear {
            text = engine.currentTask
            recents = engine.recentTasks()
            focused = true
        }
    }

    private func commit() {
        engine.setTask(text)
        dismiss()
    }
}
