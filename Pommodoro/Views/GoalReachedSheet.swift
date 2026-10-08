import SwiftUI

/// Aparece una vez, justo al cruzar el objetivo diario. El valor de la técnica
/// está en parar, no en seguir sumando: una app de foco honesta te anima a
/// cerrarla, no te retiene con un contador que solo sube.
struct GoalReachedSheet: View {
    let summary: String
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(engine.phase.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Objetivo del día cumplido")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Text(summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Cerrar por hoy")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(engine.phase.tint)
                .foregroundStyle(Theme.base)
                .clipShape(Capsule())

                Button {
                    dismiss()
                } label: {
                    Text("Seguir un poco más")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.base)
        .preferredColorScheme(.dark)
    }
}
