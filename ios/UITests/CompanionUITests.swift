import XCTest

final class CompanionUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-demo"]
        app.launch()
        tap("connection.preview")
    }

    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func tap(_ id: String) {
        let control = element(id)
        XCTAssertTrue(control.waitForExistence(timeout: 10), "Missing \(id)\n\(app.debugDescription)")
        for _ in 0..<4 {
            if control.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(control.isHittable, "Offscreen \(id)")
        control.tap()
    }

    func finishTrip(arrival: String = "我来啦！") {
        tap("travel.start")
        XCTAssertTrue(app.staticTexts[arrival].waitForExistence(timeout: 10))
        tap("travel.complete")
    }

    func checkStat(_ name: String, value: Int) {
        let stat = element("stat.\(name)")
        XCTAssertTrue(stat.waitForExistence(timeout: 10))
        XCTAssertTrue(stat.label.contains("，\(value)，"), stat.label)
    }

    func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRoundTripHasNoPhoneCareAndPreservesState() {
        tap("travel.open");finishTrip()
        XCTAssertFalse(element("care.pet").exists)
        XCTAssertFalse(element("care.play").exists)
        XCTAssertFalse(element("care.menu").exists)
        checkStat("happiness",value:75);checkStat("energy",value:80)
        tap("travel.open");finishTrip(arrival:"已经回到挂件啦")
        checkStat("happiness",value:75);checkStat("energy",value:80)
        XCTAssertTrue(app.staticTexts["一起走过的足迹"].exists)
        attachScreen("Pomi-home-and-journal")
    }
    func testWarehouseOpenBoxAndSeaPreview() {
        tap("tab.1")
        XCTAssertTrue(app.staticTexts["把日子装进小屋"].waitForExistence(timeout:5))
        tap("world.box")
        tap("world.confirm")
        app.swipeDown()
        attachScreen("Pomi-cottage-inventory")
        app.segmentedControls.buttons["放生海"].tap()
        tap("world.fish")
        XCTAssertTrue(app.staticTexts["捞取机会 2 / 3"].exists)
        attachScreen("Pomi-sea")
        tap("tab.0")
        checkStat("energy",value:70)
    }

    func testFoodConfirmationAndDecorationRelease() {
        tap("tab.1")
        tap("world.item.berry");tap("world.food")
        tap("world.confirm")
        XCTAssertFalse(element("world.item.berry").exists)
        tap("world.item.plant");tap("world.decorate")
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["窗边小草"].firstMatch.exists)
        // The placed item remains in inventory; retrieve before releasing.
        tap("world.item.plant");tap("world.decorate")
        tap("world.item.plant");tap("world.release")
        app.buttons["确认放生"].tap()
        XCTAssertTrue(element("world.item.plant").waitForNonExistence(timeout:5),app.debugDescription)
        tap("tab.0");checkStat("energy",value:100)
    }

}

final class ConnectionUITests: XCTestCase {
    func testLaunchGateAndFailedConnectionStayOnSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["connection.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab.0"].exists)
        app.buttons["connection.usb"].tap()
        XCTAssertFalse(app.buttons["hardware.connect"].isEnabled)
        let host = app.textFields["hardware.host"]
        host.tap()
        let previous = host.value as? String ?? ""
        host.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "invalid")
        let token = app.secureTextFields["hardware.token"]
        token.tap()
        token.typeText("ui-test")
        app.buttons["hardware.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.title"].exists)
        XCTAssertFalse(app.buttons["tab.0"].exists)
        XCTAssertTrue(app.staticTexts["hardware.status"].label.contains(".local"))
        app.buttons["connection.preview"].tap()
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout: 10))
        app.buttons["tab.2"].tap()
        app.swipeUp()
        let settings = app.buttons["hardware.settings"]
        if !settings.isHittable { app.swipeUp() }
        settings.tap()
        XCTAssertTrue(app.staticTexts["connection.title"].waitForExistence(timeout: 5))
    }
}

final class MotionDebugUITests: XCTestCase {
    func testMotionLabWorksWithoutConnectionAndCanBeReset() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-demo"]
        app.launch()
        let entry = app.buttons["motion.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.buttons["motion.walk"].waitForExistence(timeout: 5))
        app.buttons["motion.walk"].tap()
        XCTAssertEqual(app.staticTexts["motion.status"].label, "正在走路")
        app.buttons["motion.stop"].tap()
        XCTAssertEqual(app.staticTexts["motion.status"].label, "停下休息")
        app.buttons["motion.shake"].tap()
        XCTAssertEqual(app.staticTexts["motion.status"].label, "咦？轻轻晃了一下")
        app.buttons["motion.reset"].tap()
        XCTAssertEqual(app.staticTexts["motion.status"].label, "停下休息")
        app.buttons["motion.close"].tap()
        XCTAssertTrue(app.staticTexts["connection.title"].exists)
        XCTAssertFalse(app.buttons["tab.0"].exists)
    }
}

final class PetNameUITests: XCTestCase {
    func testCustomNameUpdatesHomeAndSurvivesRestart() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-demo"]
        app.launch()
        let preview = app.buttons["connection.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        if !preview.isHittable { app.swipeUp() }
        preview.tap()
        app.buttons["tab.2"].tap()
        let name = app.textFields["pet.name"]
        for _ in 0..<4 { if name.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(name.exists)
        name.tap()
        let old = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "momo")
        app.buttons["pet.name.save"].tap()
        XCTAssertTrue(app.staticTexts["名字已保存"].waitForExistence(timeout: 5))
        app.buttons["tab.0"].tap()
        XCTAssertTrue(app.staticTexts["momo的小屋"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let resume = app.buttons["connection.preview"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        if !resume.isHittable { app.swipeUp() }
        resume.tap()
        XCTAssertTrue(app.staticTexts["momo的小屋"].waitForExistence(timeout: 5))
    }
}

final class BluetoothConnectionUITests: XCTestCase {
    func testBluetoothIsDefaultAndUSBRemainsOptional() {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--reset-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["bluetooth.scan"].waitForExistence(timeout:10))
        XCTAssertFalse(app.textFields["hardware.host"].exists)
        app.buttons["connection.usb"].tap()
        XCTAssertTrue(app.textFields["hardware.host"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["bluetooth.scan"].exists)
        app.buttons["connection.bluetooth"].tap()
        XCTAssertTrue(app.buttons["bluetooth.scan"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["hardware.connect"].exists)
        XCTAssertFalse(app.buttons["tab.0"].exists)
    }
}
