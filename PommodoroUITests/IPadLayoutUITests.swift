import XCTest

final class IPadLayoutUITests: XCTestCase {
    func testNativeLayoutInBothOrientations() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Distribución específica de iPad")
        continueAfterFailure = false
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-engine.phase", "work", "-engine.runState", "idle",
                               "-immersionModeID", "never"]
        app.launch()
        XCTAssertTrue(app.buttons["Ajustes"].waitForExistence(timeout: 10))
        verify(app, landscape: false)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: rotated, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        verify(app, landscape: true)
        app.buttons["Sonido de fondo"].tap()
        XCTAssertTrue(app.buttons["sound.none"].waitForExistence(timeout: 5))
        app.buttons["Cerrar"].tap()
        app.buttons["Saltar a la fase siguiente"].tap()
        XCTAssertTrue(app.buttons["Empezar"].waitForExistence(timeout: 5))
        let clock = app.descendants(matching: .any)["timer.clock"].firstMatch
        XCTAssertTrue(clock.label.contains("Descanso"), clock.label)
        attach(app, name: "iPad descanso horizontal")
    }

    private func verify(_ app: XCUIApplication, landscape: Bool) {
        let clock = app.descendants(matching: .any)["timer.clock"].firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.width, 700, "Debe ejecutarse de forma nativa, sin ventana de iPhone")
        XCTAssertGreaterThan(clock.frame.width, 400, "El anillo debe crecer con la pantalla")
        XCTAssertTrue(app.frame.contains(clock.frame), "El reloj debe quedar dentro de la ventana")
        XCTAssertTrue(app.frame.contains(app.buttons["Empezar"].frame))
        XCTAssertTrue(app.buttons["Empezar"].isHittable)
        XCTAssertTrue(app.buttons["Historial"].isHittable)
        XCTAssertTrue(app.buttons["Sonido de fondo"].isHittable)
        if landscape {
            XCTAssertGreaterThan(app.buttons["Empezar"].frame.midX, clock.frame.maxX)
        }
        attach(app, name: landscape ? "iPad horizontal" : "iPad vertical")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
