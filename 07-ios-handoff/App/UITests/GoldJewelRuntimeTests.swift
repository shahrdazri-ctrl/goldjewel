import UIKit
import XCTest

/// Runtime gate for the iPhone and iPad app.
///
/// The test is deliberately not satisfied by "the process stayed alive": it
/// creates and edits a project, toggles every geometry family, proves the
/// preview's accessibility geometry and sampled pixels changed, then relaunches
/// and proves the document and the toggles came back.
///
/// XCTest's UI APIs are main-actor isolated in the Swift 6 SDK, so the whole
/// case runs on the main actor. Setup happens inside the test rather than in
/// `setUpWithError`, whose override must stay nonisolated.
@MainActor
final class GoldJewelRuntimeTests: XCTestCase {
    private var app: XCUIApplication!

    private var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    func testProjectEditingRenderingAndPersistence() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        relaunch(reset: true)

        let newProject = app.buttons["new-project"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 30),
                      "\(deviceName): project list never appeared")
        newProject.tap()

        let rows = app.descendants(matching: .any).matching(identifier: "project-row")
        XCTAssertTrue(waitForCount(rows, atLeast: 2, timeout: 10),
                      "\(deviceName): creating a project did not add a row")
        rows.element(boundBy: rows.count - 1).tap()

        let preview = app.descendants(matching: .any)["head-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30),
                      "\(deviceName): editor did not show the head preview")
        waitForPreviewGeometry(preview)

        let base = try capture("01-base", preview: preview)
        XCTAssertGreaterThan(base.inkRatio, 0.02,
                             "\(deviceName): preview rendered as a blank/background image")
        attachFullScreen("01-start")

        // Edit the document name. Appending is enough to prove the text field
        // writes through; the persisted value is checked after relaunch.
        let nameField = app.textFields["project-name"]
        scrollTo(nameField)
        nameField.tap()
        nameField.typeText(" Runtime Gate")
        dismissKeyboard()

        // Gallery rail.
        let beforeRail = try capture("02-before-rail", preview: preview)
        setToggle("rail-toggle", on: false, preview: preview)
        let withoutRail = try capture("03-rail-off", preview: preview)
        XCTAssertGreaterThan(withoutRail.difference(from: beforeRail), 0.005,
                             "\(deviceName): switching the gallery off did not change a pixel")
        setToggle("rail-toggle", on: true, preview: preview)

        // Prong domes (on by default).
        let beforeDome = try capture("04-before-dome", preview: preview)
        setToggle("dome-toggle", on: false, preview: preview)
        let withoutDome = try capture("05-dome-off", preview: preview)
        XCTAssertGreaterThan(withoutDome.difference(from: beforeDome), 0.005,
                             "\(deviceName): switching the dome off did not change a pixel")
        setToggle("dome-toggle", on: true, preview: preview)

        // Bezel (off by default).
        let beforeBezel = try capture("06-before-bezel", preview: preview)
        setToggle("bezel-toggle", on: true, preview: preview)
        let withBezel = try capture("07-bezel-on", preview: preview)
        XCTAssertGreaterThan(withBezel.difference(from: beforeBezel), 0.005,
                             "\(deviceName): enabling the bezel did not change a pixel")

        // Halo (off by default).
        let beforeHalo = try capture("08-before-halo", preview: preview)
        setToggle("halo-toggle", on: true, preview: preview)
        let withHalo = try capture("09-halo-on", preview: preview)
        XCTAssertGreaterThan(withHalo.difference(from: beforeHalo), 0.005,
                             "\(deviceName): enabling the halo did not change a pixel")

        // A parameter change that keeps the topology but moves the geometry.
        let gemSlider = app.sliders["gem-diameter"]
        scrollTo(gemSlider)
        let beforeGem = try capture("10-before-gem", preview: preview)
        gemSlider.adjust(toNormalizedSliderPosition: 0.72)
        Thread.sleep(forTimeInterval: 0.8)
        let afterGem = try capture("11-gem-larger", preview: preview)
        XCTAssertGreaterThan(afterGem.difference(from: beforeGem), 0.01,
                             "\(deviceName): moving the gem slider did not change the head")

        attachFullScreen("12-final")
        app.terminate()

        // Relaunch without the reset switch: the project, its name and the four
        // family switches must come back from projects.json.
        relaunch(reset: false)
        let savedRow = app.descendants(matching: .any)
            .matching(identifier: "project-row")
            .matching(NSPredicate(format: "label CONTAINS 'Runtime Gate'"))
            .firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 20),
                      "\(deviceName): the edited project did not survive relaunch")
        savedRow.tap()

        let restoredPreview = app.descendants(matching: .any)["head-preview"]
        XCTAssertTrue(restoredPreview.waitForExistence(timeout: 20),
                      "\(deviceName): restored project has no preview")
        let restored = try capture("13-relaunch", preview: restoredPreview)
        XCTAssertGreaterThan(restored.inkRatio, 0.02,
                             "\(deviceName): restored preview is blank")

        let restoredName = app.textFields["project-name"]
        scrollTo(restoredName)
        XCTAssertTrue((restoredName.value as? String)?.contains("Runtime Gate") == true,
                      "\(deviceName): edited name was not persisted")

        for identifier in ["rail-toggle", "dome-toggle", "bezel-toggle", "halo-toggle"] {
            let toggle = app.switches[identifier]
            scrollTo(toggle)
            XCTAssertTrue(isOn(toggle),
                          "\(deviceName): \(identifier) was not persisted as on")
        }
        attachFullScreen("14-relaunch")
    }

    // MARK: - Actions

    private func relaunch(reset: Bool) {
        app.terminate()
        var arguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { arguments.append("-reset-projects") }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 45),
                      "\(deviceName): app did not reach the foreground")
    }

    private func dismissKeyboard() {
        let done = app.buttons["dismiss-keyboard"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
            return
        }
        if app.keyboards.count > 0 {
            app.keyboards.buttons["Done"].tap()
        }
    }

    private func setToggle(_ identifier: String, on: Bool, preview: XCUIElement) {
        let toggle = app.switches[identifier]
        scrollTo(toggle)
        guard isOn(toggle) != on else { return }
        let before = preview.value as? String
        toggle.tap()
        XCTAssertEqual(isOn(toggle), on,
                       "\(deviceName): \(identifier) did not switch")
        if let before {
            let predicate = NSPredicate(format: "value != %@", before)
            let changed = XCTNSPredicateExpectation(predicate: predicate, object: preview)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed,
                           "\(deviceName): \(identifier) did not rebuild the preview")
        }
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        let value = (toggle.value as? String ?? "").lowercased()
        return value == "1" || value == "on" || value == "true"
    }

    private func waitForPreviewGeometry(_ preview: XCUIElement) {
        let predicate = NSPredicate(format: "value CONTAINS 'triangles'")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed,
                       "\(deviceName): preview never reported its triangle count")
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("\(deviceName): could not scroll to \(element)")
    }

    private func scrollToTop(preview: XCUIElement) {
        if app.statusBars.firstMatch.exists {
            app.statusBars.firstMatch.tap()
        }
        for _ in 0..<4 {
            if preview.isHittable { return }
            app.swipeDown()
        }
    }

    private func waitForCount(_ query: XCUIElementQuery, atLeast count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return query.count >= count
    }

    // MARK: - Screenshots and pixels

    private func capture(_ name: String, preview: XCUIElement) throws -> PreviewFrame {
        scrollToTop(preview: preview)
        XCTAssertTrue(preview.waitForExistence(timeout: 10),
                      "\(deviceName): preview disappeared before \(name)")
        let screenshot = preview.screenshot()
        attach(screenshot, name: "\(deviceName)-\(name)")
        return try PreviewFrame(screenshot: screenshot)
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachFullScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(deviceName)-\(name)-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// A 48×48 luminance sample of the preview plus the fraction of cells bright
/// enough to be metal or a gem rather than the dark canvas background.
struct PreviewFrame {
    let luminance: [UInt8]
    let inkRatio: Double

    init(screenshot: XCUIScreenshot) throws {
        guard let image = screenshot.image.cgImage else {
            throw RuntimeGateError.noPixels
        }
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { throw RuntimeGateError.noPixels }

        var values = [UInt8](repeating: 0, count: side * side)
        var ink = 0
        for index in 0..<(side * side) {
            let r = Double(pixels[index * 4])
            let g = Double(pixels[index * 4 + 1])
            let b = Double(pixels[index * 4 + 2])
            let value = UInt8(min(255, (0.2126 * r + 0.7152 * g + 0.0722 * b).rounded()))
            values[index] = value
            if value >= 45 { ink += 1 }
        }
        self.luminance = values
        self.inkRatio = Double(ink) / Double(side * side)
    }

    func difference(from other: PreviewFrame) -> Double {
        guard luminance.count == other.luminance.count else { return 1 }
        var changed = 0
        for (left, right) in zip(luminance, other.luminance)
        where abs(Int(left) - Int(right)) > 10 {
            changed += 1
        }
        return Double(changed) / Double(luminance.count)
    }
}

enum RuntimeGateError: Error {
    case noPixels
}
