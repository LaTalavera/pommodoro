#if os(macOS)
import Foundation
import Testing
@testable import Pommodoro

@MainActor
@Suite("Insignia del Dock")
struct DockBadgeTests {
    @Test("Sin bloque empezado no hay insignia")
    func idleHasNoBadge() {
        #expect(DockBadge.label(runState: .idle, remaining: 1500) == nil)
    }

    @Test("Redondea los minutos hacia arriba, como el reloj")
    func roundsMinutesUp() {
        #expect(DockBadge.label(runState: .running, remaining: 1500) == "25")
        #expect(DockBadge.label(runState: .running, remaining: 1440.2) == "25")
        #expect(DockBadge.label(runState: .running, remaining: 1440) == "24")
        #expect(DockBadge.label(runState: .paused, remaining: 61) == "2")
    }

    @Test("El último minuto se cuenta en segundos")
    func lastMinuteInSeconds() {
        #expect(DockBadge.label(runState: .running, remaining: 60) == "1")
        // 59,4 s se muestra 01:00 en el reloj, así que sigue siendo «1».
        #expect(DockBadge.label(runState: .running, remaining: 59.4) == "1")
        #expect(DockBadge.label(runState: .running, remaining: 59) == "59s")
        #expect(DockBadge.label(runState: .running, remaining: 5) == "5s")
    }
}
#endif
