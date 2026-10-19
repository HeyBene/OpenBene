import XCTest

final class CapturePresentationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openCapture(_ app: XCUIApplication) {
        let create = app.buttons["采集新地图"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let begin = app.buttons["开始采集"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        if !begin.isHittable { app.swipeUp() }
        begin.tap()
        XCTAssertTrue(app.staticTexts["采集地图"].waitForExistence(timeout: 5),
                      "The capture page must appear without backgrounding the app.")
        XCTAssertTrue(app.buttons["确认支架处出发位置"].exists)
        XCTAssertTrue(app.buttons["follow.start"].isHittable, "The follow entry must be visible in the capture viewport.")
        XCTAssertFalse(app.buttons["follow.start"].isEnabled, "Capture cannot drive before mounting and selecting a robot.")
        XCTAssertTrue(app.buttons["follow.stop"].isHittable)
        let entry = XCTAttachment(screenshot: app.screenshot())
        entry.name = "Visible capture-follow controls"
        entry.lifetime = .keepAlways
        add(entry)
        for _ in 0..<4 where !app.buttons["取消"].isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.buttons["取消"].isHittable)
    }

    func testCaptureAppearsOnFirstAndRepeatedPresentation() {
        let app = XCUIApplication()
        app.launch()
        for attempt in 1...2 {
            openCapture(app)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Capture presentation \(attempt)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["取消"].tap()
        }
    }

    func testCameraActuallyRendersOnDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The simulator cannot run an ARKit camera session.")
        #else
        let app = XCUIApplication()
        app.launch()
        openCapture(app)
        let preview = app.otherElements["ar.camera.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        let rendered = NSPredicate(format: "value == %@", "已显示")
        expectation(for: rendered, evaluatedWith: preview)
        waitForExpectations(timeout: 15)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Rendered camera on device"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["取消"].tap()
        #endif
    }

    func testPwmSettingsPersistAcrossAppRelaunchWithoutRobot() throws {
        let app = XCUIApplication()
        app.launch()

        func reveal(_ element: XCUIElement, up: Bool = true) {
            for _ in 0..<7 {
                if element.isHittable { return }
                if up { app.swipeUp() } else { app.swipeDown() }
            }
            XCTAssertTrue(element.isHittable)
        }
        func openSettings() {
            let button = app.buttons["pwm.open"]
            reveal(button)
            button.tap()
            XCTAssertTrue(app.staticTexts["pwm.saved"].waitForExistence(timeout: 5))
        }
        func adjust(_ identifier: String, increment: Bool) {
            let stepper = app.steppers[identifier]
            reveal(stepper, up: false)
            stepper.buttons[identifier + (increment ? "-Increment" : "-Decrement")].tap()
        }
        func save() {
            let button = app.buttons["pwm.save"]
            reveal(button)
            button.tap()
        }

        openSettings()
        let originalLabel = app.staticTexts["pwm.saved"].label
        let regex = try NSRegularExpression(pattern: "[0-9]+")
        let values = regex.matches(in: originalLabel, range: NSRange(originalLabel.startIndex..., in: originalLabel))
            .compactMap { Range($0.range, in: originalLabel).flatMap { Int(originalLabel[$0]) } }
        XCTAssertEqual(values.count, 3)
        let driveUp = values[0] < 255
        let leftUp = values[1] < 255
        let rightUp = values[2] == 0
        adjust("pwm.drive", increment: driveUp)
        adjust("pwm.turn.left", increment: leftUp)
        adjust("pwm.turn.right", increment: rightUp)
        let expected = "当前已保存：直行 \(values[0] + (driveUp ? 1 : -1))，左转 \(values[1] + (leftUp ? 1 : -1))，右转 \(values[2] + (rightUp ? 1 : -1))"
        let test = app.buttons["前进 1 秒"]
        reveal(test)
        XCTAssertFalse(test.isEnabled, "No robot was selected; testing must stay disabled.")
        save()
        reveal(app.staticTexts["pwm.saved"], up: false)
        XCTAssertEqual(app.staticTexts["pwm.saved"].label, expected)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PWM settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        openSettings()
        XCTAssertEqual(app.staticTexts["pwm.saved"].label, expected)
        adjust("pwm.drive", increment: !driveUp)
        adjust("pwm.turn.left", increment: !leftUp)
        adjust("pwm.turn.right", increment: !rightUp)
        save()
        reveal(app.staticTexts["pwm.saved"], up: false)
        XCTAssertEqual(app.staticTexts["pwm.saved"].label, originalLabel)
        app.buttons["完成"].tap()
    }
}
