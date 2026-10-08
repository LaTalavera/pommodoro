#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Haptics {
    enum Style {
        case light, medium, soft, rigid
    }

    enum Outcome {
        case success
    }

    @MainActor
    static func impact(_ style: Style) {
        guard AppSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle = switch style {
        case .light: .light
        case .medium: .medium
        case .soft: .soft
        case .rigid: .rigid
        }
        UIImpactFeedbackGenerator(style: uiStyle).impactOccurred()
        #else
        // Solo hay respuesta háptica en el trackpad, y solo si el dedo está encima.
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    @MainActor
    static func notify(_ outcome: Outcome) {
        guard AppSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }
}
