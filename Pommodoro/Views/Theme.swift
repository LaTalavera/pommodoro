import SwiftUI

enum Theme {
    static let base = Color(red: 0.04, green: 0.04, blue: 0.055)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)

    static func time(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded).monospacedDigit()
    }
}

/// Fondo a pantalla completa: negro con un halo del color de la fase que
/// respira despacio. Es lo único que cambia entre trabajo y descanso, así que
/// el estado se reconoce de un vistazo sin leer nada.
struct PhaseBackground: View {
    let phase: PomodoroPhase
    let isRunning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            Theme.base
            RadialGradient(
                colors: [phase.tint.opacity(isRunning ? 0.38 : 0.22), .clear],
                center: .init(x: 0.5, y: 0.34),
                startRadius: 0,
                endRadius: breathe ? 460 : 380
            )
            .blur(radius: 40)

            RadialGradient(
                colors: [phase.tint.opacity(0.16), .clear],
                center: .init(x: 0.12, y: 0.92),
                startRadius: 0,
                endRadius: 320
            )
            .blur(radius: 50)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.9), value: phase)
        .animation(.easeInOut(duration: 0.9), value: isRunning)
        .onAppear {
            // Con «Reducir movimiento» el halo se queda quieto: es una animación
            // en bucle infinito justo detrás de algo que se mira fijamente.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

/// Anillo de progreso de la fase actual.
struct ProgressRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.0001))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint, tint.opacity(0.9)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.5), radius: 12)
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

/// Botón circular translúcido usado en la barra de controles.
struct CircleButton: View {
    let symbol: String
    /// Qué hace el botón, dicho en palabras. Sin esto VoiceOver solo anuncia
    /// «botón», o el nombre del símbolo de SF Symbols.
    let label: String
    var size: CGFloat = 52
    var prominent: Bool = false
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 30 : 18, weight: .medium))
                .foregroundStyle(prominent ? Theme.base : .white)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.card))
                        .overlay(Circle().stroke(Theme.stroke, lineWidth: prominent ? 0 : 1))
                }
                .shadow(color: prominent ? tint.opacity(0.45) : .clear, radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }
}
