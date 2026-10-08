import SwiftUI

extension View {
    /// Barra de estado y superposiciones del sistema solo existen en iOS; en el
    /// Mac la ventana no tiene nada equivalente que ocultar.
    @ViewBuilder
    func hidingSystemChrome(_ hidden: Bool) -> some View {
        #if os(iOS)
        self
            .statusBarHidden(hidden)
            .persistentSystemOverlays(hidden ? .hidden : .automatic)
        #else
        self
        #endif
    }

    /// Título compacto en las hojas con barra de navegación (iOS).
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension View {
    /// En iOS las hojas se dimensionan solas; en el Mac se quedan al tamaño del
    /// contenido y hay que darles uno cómodo.
    @ViewBuilder
    func sheetSizing(minHeight: CGFloat = 560) -> some View {
        #if os(macOS)
        self.frame(minWidth: 480, idealWidth: 520, minHeight: minHeight, idealHeight: minHeight + 120)
        #else
        self
        #endif
    }
}
