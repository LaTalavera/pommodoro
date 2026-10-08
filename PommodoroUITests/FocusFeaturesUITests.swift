import XCTest

final class FocusFeaturesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(task: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-engine.phase", "work", "-engine.runState", "idle",
            "-engine.currentTask", task, "-workMinutes", "25",
            "-autoStartBreaks", "NO", "-immersionModeID", "never", "-soundID", "none"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Empezar"].waitForExistence(timeout: 10))
        app.buttons["Empezar"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Permitir", "Don’t Allow", "No permitir"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) { button.tap(); break }
        }
        return app
    }

    func testAbandonedEffortAppearsInHistory() {
        let app = launch(task: "Prueba de esfuerzo parcial")
        // The app deliberately ignores accidental sessions shorter than 30 s.
        Thread.sleep(forTimeInterval: 32)
        app.buttons["Saltar a la fase siguiente"].tap()
        app.buttons["Historial"].tap()
        XCTAssertTrue(app.staticTexts["< 1 min"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["El tiempo concentrado incluye los bloques abandonados. Los descansos no cuentan."].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Prueba de esfuerzo parcial'")).firstMatch.exists)
        attach(app, name: "Historial con esfuerzo parcial")
    }

    func testLiveActivityInDynamicIsland() {
        let app = launch(task: "Prueba de Live Activity")
        // Give the async ActivityKit request time to reach SpringBoard.
        Thread.sleep(forTimeInterval: 2)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035))
            .press(forDuration: 1)
        let task = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Prueba de Live Activity'")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10), springboard.debugDescription)
        attach(springboard, name: "Dynamic Island expandida")
        // Dismiss the expanded island before activating the app: otherwise
        // XCTest may find an offscreen button and synthesize a tap at (-1, -1).
        XCUIDevice.shared.press(.home)
        app.activate()
        let pauseReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: app.buttons["Pausar"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pauseReady], timeout: 5), .completed)
        app.buttons["Pausar"].tap()
        XCTAssertTrue(app.buttons["Empezar"].waitForExistence(timeout: 5))
        // ActivityKit delivers updates asynchronously to the widget process.
        Thread.sleep(forTimeInterval: 2)
        // Notification Center uses the same presentation as the Lock Screen.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.005))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8)))
        for label in ["Allow", "Permitir"] {
            let allowActivity = springboard.buttons[label]
            if allowActivity.exists { allowActivity.tap(); break }
        }
        let paused = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'En pausa' AND label CONTAINS 'Toca para continuar'")).firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 10), springboard.debugDescription)
        attach(springboard, name: "Pantalla bloqueada en pausa")
        XCUIDevice.shared.press(.home)
        app.activate()
        app.buttons["Reiniciar la fase"].tap()
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
