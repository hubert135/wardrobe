import XCTest

/// Happy path: add a garment, generate outfits, tap "I'm wearing this".
/// Runs with `-uiTesting`: in-memory store, 7 seeded garments, mock weather, offline AI (local engine).
final class WardrobeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAddGarmentGenerateOutfitAndWearIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // 1. Add the 8th garment manually.
        app.tabBars.buttons["Closet"].tap()
        app.buttons["closet.add"].tap()
        app.segmentedControls.buttons["Manual"].tap()

        let name = app.textFields["garment.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Beige chinos")
        app.buttons["manual.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Beige chinos"].firstMatch.waitForExistence(timeout: 5))

        // 2. Generate outfits.
        app.tabBars.buttons["Today"].tap()
        app.buttons["today.suggest"].tap()

        // 3. Wear the first one.
        let wear = app.buttons.matching(identifier: "outfit.wear").firstMatch
        XCTAssertTrue(wear.waitForExistence(timeout: 10))
        wear.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Saved to your history. Have a good day!"].exists)
        alert.buttons["OK"].tap()

        // 4. It shows up in History.
        app.tabBars.buttons["Outfits"].tap()
        app.buttons["History"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "&")).firstMatch.waitForExistence(timeout: 5))
    }
}
