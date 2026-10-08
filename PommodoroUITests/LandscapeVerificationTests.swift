import XCTest

/// No comprueba comportamiento — sirve para capturar el modo horizontal real
/// girando el simulador de verdad (vía `XCUIDevice`, no AppleScript), y adjunta
/// las capturas al resultado para poder revisarlas.
final class LandscapeVerificationTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapturePortraitAndLandscape() throws {
        let app = XCUIApplication()
        app.launch()

        // Puede salir la petición de notificaciones; si aparece, se descarta.
        let allow = app.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }

        attach(app, named: "01-vertical")

        XCUIDevice.shared.orientation = .landscapeLeft
        // La rotación es animada; sin esta espera la captura llega a mitad de giro.
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, named: "02-horizontal")
        // Ventana corta para capturar el mismo instante con `simctl io
        // screenshot` desde fuera, sin quedarse inactivo tanto tiempo como
        // para que el simulador devuelva a Home por su cuenta.
        Thread.sleep(forTimeInterval: 2)

        // Arranca un bloque para comprobar el modo horizontal con el reloj en marcha.
        let ring = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'listo' OR label CONTAINS 'en marcha'")).firstMatch
        if ring.waitForExistence(timeout: 3) {
            ring.tap()
            Thread.sleep(forTimeInterval: 1.5)
            attach(app, named: "03-horizontal-en-marcha")
        }

        XCUIDevice.shared.orientation = .portrait
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
