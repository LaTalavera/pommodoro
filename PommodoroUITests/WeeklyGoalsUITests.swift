import XCTest

final class WeeklyGoalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(history: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-engine.phase", "work", "-engine.runState", "idle",
                               "-dailyGoalModeID", history ? "disabled" : "blocks",
                               "-dailyGoalMinutes", "120", "-dailyGoal", "8", "-soundID", "none"]
        if history { app.launchArguments.append("--ui-testing-history-fixture") }
        app.launch()
        XCTAssertTrue(app.buttons["Ajustes"].waitForExistence(timeout: 10))
        return app
    }

    func testWeeklyTasksAndNavigation() {
        let app = launch(history: true)
        app.buttons["Historial"].tap()
        XCTAssertTrue(app.staticTexts["Esta semana"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Semana siguiente"].isEnabled)
        let study = app.descendants(matching: .any)["history.task.task:estudiar"]
        app.swipeUp()
        XCTAssertTrue(study.waitForExistence(timeout: 5))
        XCTAssertTrue(study.label.contains("30 min"), study.label)
        XCTAssertTrue(study.label.contains("1 bloque completado"), study.label)
        XCTAssertTrue(study.label.contains("6 interrupciones"), study.label)
        attach(app, name: "Resumen semanal por tarea")
        app.swipeDown()
        app.swipeDown()
        app.buttons["Semana anterior"].tap()
        let previous = app.descendants(matching: .any)["history.task.task:semana pasada"]
        app.swipeUp()
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertTrue(previous.label.contains("15 min"), previous.label)
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(app.buttons["Semana siguiente"].isEnabled)
        app.buttons["Semana anterior"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["history.emptyWeek"].waitForExistence(timeout: 5))
    }

    func testGoalModesCanBeChangedAndDisabled() {
        let app = launch()
        app.buttons["Ajustes"].tap()
        let picker = app.buttons["goal.mode"]
        for _ in 0..<3 {
            if picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Minutos"].tap()
        XCTAssertTrue(app.steppers["goal.minutes"].waitForExistence(timeout: 5))
        app.steppers["goal.minutes"].buttons.element(boundBy: 1).tap()
        attach(app, name: "Objetivo diario en minutos")
        app.buttons["Listo"].tap()
        let progress = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Progreso del ciclo'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue((progress.value as? String)?.contains("0/125 min hoy") == true)
        app.buttons["Ajustes"].tap()
        for _ in 0..<3 {
            if picker.isHittable { break }
            app.swipeUp()
        }
        picker.tap()
        app.buttons["Sin objetivo"].tap()
        XCTAssertTrue(app.staticTexts["Puedes concentrarte sin una meta diaria."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.steppers["goal.minutes"].exists)
        XCTAssertFalse(app.steppers["goal.blocks"].exists)
        attach(app, name: "Objetivo diario desactivado")
        picker.tap()
        app.buttons["Bloques"].tap()
        XCTAssertTrue(app.steppers["goal.blocks"].waitForExistence(timeout: 5))
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
