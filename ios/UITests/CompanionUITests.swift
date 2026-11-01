import XCTest

final class CompanionUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-demo"]
        app.launch()
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

    func testRoundTripAndCarePreserveState() {
        attachScreen("01-device-residence")
        tap("travel.open")
        finishTrip()
        tap("care.pet")
        checkStat("happiness", value: 85)
        tap("care.play")
        checkStat("happiness", value: 100)
        checkStat("energy", value: 68)
        attachScreen("02-phone-room")
        tap("travel.open")
        finishTrip(arrival: "已经回到挂件啦")
        tap("travel.open")
        finishTrip()
        checkStat("happiness", value: 100)
        checkStat("energy", value: 68)
        tap("tab.1")
        XCTAssertTrue(app.staticTexts["来手机小屋做客"].firstMatch.waitForExistence(timeout: 5))
        attachScreen("03-journal")
    }

    func testInterruptedTripSurvivesAppRestart() {
        tap("tab.2")
        tap("demo.interrupt")
        tap("tab.0")
        tap("travel.open")
        tap("travel.start")
        XCTAssertTrue(app.staticTexts["小旅程，暂停了一下"].waitForExistence(timeout: 10))
        attachScreen("04-interrupted-trip")
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        tap("travel.resume")
        finishTrip()
        tap("care.pet")
        checkStat("happiness", value: 85)
        checkStat("energy", value: 80)
        attachScreen("05-resumed-trip")
    }

    func testSleepAndFeedUseCareMenu() {
        tap("travel.open")
        finishTrip()
        tap("care.menu")
        tap("care.sleep")
        tap("care.pet")
        checkStat("happiness", value: 75)
        tap("care.menu")
        tap("care.sleep")
        tap("care.menu")
        tap("care.feed")
        checkStat("energy", value: 100)
    }
}
