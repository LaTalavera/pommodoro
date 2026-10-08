import XCTest

final class SoundLibraryUITests: XCTestCase {
    func testSelectionAndSilencePersistWhenClosing() {
        continueAfterFailure = false
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-engine.phase", "work", "-engine.runState", "idle",
                               "-soundID", "rain", "-breakSoundID", "ocean"]
        app.launch()
        let chip = app.buttons["Sonido de fondo"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.value as? String, "Silencio")
        chip.tap()
        app.buttons["Uniformes"].tap()
        app.buttons["sound.fan"].tap()
        XCTAssertTrue(app.buttons["Detener escucha"].waitForExistence(timeout: 3))
        app.buttons["sound.preview"].tap()
        XCTAssertEqual(app.buttons["sound.preview"].label, "Escuchar selección")
        app.buttons["Cerrar"].tap()
        XCTAssertTrue((chip.value as? String ?? "").contains("Ventilador"))
        chip.tap()
        app.buttons["Naturaleza"].tap()
        app.buttons["sound.softRain"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Biblioteca de sonidos"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cerrar"].tap()
        XCTAssertTrue((chip.value as? String ?? "").contains("Lluvia suave"))
        chip.tap()
        app.buttons["sound.none"].tap()
        app.buttons["Cerrar"].tap()
        XCTAssertEqual(chip.value as? String, "Silencio")
        app.terminate()
        app.launch()
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.value as? String, "Silencio")
    }
}
