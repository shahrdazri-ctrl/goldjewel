import Darwin
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
        // Bound a wedged run instead of letting xcodebuild sit for its full
        // job timeout; a timeout is a test failure, not a skipped check.
        executionTimeAllowance = 420
        continueAfterFailure = false
        app = XCUIApplication()
        relaunch(reset: true)
        step("launched")

        let newProject = app.buttons["new-project"]
        // On iPhone the compact split view can restore the selected project's
        // detail at launch, so walk back to the list before looking for its
        // toolbar button.
        if !newProject.waitForExistence(timeout: 6) {
            returnToProjectList()
        }
        XCTAssertTrue(newProject.waitForExistence(timeout: 20),
                      "\(deviceName): project list never appeared")
        newProject.tap()

        let rows = app.descendants(matching: .any).matching(identifier: "project-row")
        let preview = app.descendants(matching: .any)["head-preview"]
        // Selecting the new project pushes the editor on iPhone but leaves the
        // list visible on iPad, so accept either, then require the row to exist
        // when the list is still on screen.
        if !preview.waitForExistence(timeout: 12) {
            XCTAssertTrue(waitForCount(rows, atLeast: 2, timeout: 10),
                          "\(deviceName): creating a project did not add a row")
            rows.element(boundBy: rows.count - 1).tap()
        }
        XCTAssertTrue(preview.waitForExistence(timeout: 30),
                      "\(deviceName): editor did not show the head preview")
        waitForPreviewGeometry(preview)
        step("preview ready")

        let base = try capture("01-base", preview: preview)
        XCTAssertGreaterThan(base.goldRatio, 0.02,
                             "\(deviceName): preview contains almost no metal pixels (\(base.goldRatio)); it is blank or background-only")
        attachFullScreen("01-start")
        step("base captured")

        // Edit the document name. Appending is enough to prove the text field
        // writes through; the persisted value is checked after relaunch.
        let nameField = app.textFields["project-name"]
        scrollTo(nameField)
        nameField.tap()
        nameField.typeText(" Runtime Gate")
        nameField.typeText("\n")
        dismissKeyboard()
        XCTAssertFalse(app.keyboards.firstMatch.exists,
                       "\(deviceName): keyboard stayed up and would cover the controls")
        step("name edited")

        // Gallery rail.
        let beforeRail = try capture("02-before-rail", preview: preview)
        step("rail before")
        setToggle("rail-toggle", on: false, preview: preview)
        step("rail off")
        let withoutRail = try capture("03-rail-off", preview: preview)
        XCTAssertGreaterThan(withoutRail.difference(from: beforeRail), 0.005,
                             "\(deviceName): switching the gallery off changed only \(withoutRail.difference(from: beforeRail)) of the preview")
        setToggle("rail-toggle", on: true, preview: preview)
        step("rail restored")

        // Prong domes (on by default).
        let beforeDome = try capture("04-before-dome", preview: preview)
        setToggle("dome-toggle", on: false, preview: preview)
        step("dome off")
        let withoutDome = try capture("05-dome-off", preview: preview)
        XCTAssertGreaterThan(withoutDome.difference(from: beforeDome), 0.005,
                             "\(deviceName): switching the dome off changed only \(withoutDome.difference(from: beforeDome)) of the preview")
        setToggle("dome-toggle", on: true, preview: preview)
        step("dome restored")

        // Bezel (off by default).
        let beforeBezel = try capture("06-before-bezel", preview: preview)
        setToggle("bezel-toggle", on: true, preview: preview)
        step("bezel on")
        let withBezel = try capture("07-bezel-on", preview: preview)
        XCTAssertGreaterThan(withBezel.difference(from: beforeBezel), 0.005,
                             "\(deviceName): enabling the bezel changed only \(withBezel.difference(from: beforeBezel)) of the preview")

        // Halo (off by default).
        let beforeHalo = try capture("08-before-halo", preview: preview)
        setToggle("halo-toggle", on: true, preview: preview)
        step("halo on")
        let withHalo = try capture("09-halo-on", preview: preview)
        XCTAssertGreaterThan(withHalo.difference(from: beforeHalo), 0.005,
                             "\(deviceName): enabling the halo changed only \(withHalo.difference(from: beforeHalo)) of the preview")

        // A parameter change that keeps the topology but moves the geometry.
        let gemSlider = app.sliders["gem-diameter"]
        scrollTo(gemSlider)
        let beforeGem = try capture("10-before-gem", preview: preview)
        let beforeGemValue = preview.value as? String
        gemSlider.adjust(toNormalizedSliderPosition: 0.72)
        // A jump from 6.5 mm to nearly 10 mm rebuilds every family. Wait for
        // the new mesh to be published instead of assuming a fixed pause.
        let rebuilt = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND value != %@", beforeGemValue ?? ""),
            object: preview
        )
        XCTAssertEqual(XCTWaiter.wait(for: [rebuilt], timeout: 30), .completed,
                       "\(deviceName): the preview did not rebuild after the gem diameter changed")
        step("gem moved")
        let afterGem = try capture("11-gem-larger", preview: preview)
        XCTAssertGreaterThan(afterGem.difference(from: beforeGem), 0.01,
                             "\(deviceName): moving the gem slider changed only \(afterGem.difference(from: beforeGem)) of the head")

        attachFullScreen("12-final")
        step("editing complete")
        app.terminate()

        // Relaunch without the reset switch: the project, its name and the four
        // family switches must come back from projects.json.
        relaunch(reset: false)
        step("relaunched")
        let savedRow = app.descendants(matching: .any)
            .matching(identifier: "project-row")
            .matching(NSPredicate(format: "label CONTAINS 'Runtime Gate'"))
            .firstMatch
        if !savedRow.waitForExistence(timeout: 6) {
            returnToProjectList()
        }
        XCTAssertTrue(savedRow.waitForExistence(timeout: 20),
                      "\(deviceName): the edited project did not survive relaunch")
        savedRow.tap()

        let restoredPreview = app.descendants(matching: .any)["head-preview"]
        XCTAssertTrue(restoredPreview.waitForExistence(timeout: 20),
                      "\(deviceName): restored project has no preview")
        let restored = try capture("13-relaunch", preview: restoredPreview)
        XCTAssertGreaterThan(restored.goldRatio, 0.02,
                             "\(deviceName): restored preview is blank (\(restored.goldRatio) metal pixels)")

        step("restored preview captured")
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
        step("persistence verified")
    }

    /// Surfaced in the CI log while the test is still running, and as an
    /// activity in the result bundle if it fails or hangs.
    private func step(_ name: String) {
        print("RUNTIME_STEP \(deviceName): \(name)")
        fflush(stdout)
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
        guard app.keyboards.count > 0 else { return }
        let toolbarDone = app.buttons["dismiss-keyboard"]
        if toolbarDone.exists && toolbarDone.isHittable {
            toolbarDone.tap()
        }
        if app.keyboards.count > 0 {
            let keyboardDone = app.keyboards.buttons["Done"]
            if keyboardDone.exists { keyboardDone.tap() }
        }
    }

    private func setToggle(_ identifier: String, on: Bool, preview: XCUIElement) {
        let toggle = app.switches[identifier]
        scrollTo(toggle)
        // A tap during deceleration only stops the scroll; let the view settle
        // so the switch receives the tap.
        Thread.sleep(forTimeInterval: 0.8)
        guard isOn(toggle) != on else { return }
        let before = preview.value as? String
        // Aim at the control at the trailing edge rather than the row's centre,
        // in case the merged accessibility element spans the whole row.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        // The switch animates and SwiftUI commits the new state on the next
        // run loop; poll the real value instead of sampling it once.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && isOn(toggle) != on {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if isOn(toggle) != on {
            attachFullScreen("stuck-\(identifier)")
        }
        XCTAssertEqual(isOn(toggle), on,
                       "\(deviceName): \(identifier) did not switch after a tap")
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

    /// The editor is a single long scroll view and the controls are exercised
    /// out of document order, so every lookup starts by returning to the top
    /// and then scrolls down. Scrolling only downward could never reach a
    /// control that sits above the current position.
    ///
    /// The head preview consumes drags to rotate the model, and it covers the
    /// window centre on iPad, so `app.swipeUp()` rotates the head instead of
    /// scrolling. These drags start in the lower content area, below the
    /// preview, and never at the centre of the screen.
    private func scrollTo(_ element: XCUIElement) {
        scrollToTop()
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            scrollDownOnePage()
        }
        XCTFail("\(deviceName): could not scroll to \(element)")
    }

    private func scrollToTop() {
        // Tapping the status bar asks the system to scroll the active scroll
        // view to the top without touching the preview's drag gesture. Two
        // margin drags are the fallback if the system ignores it.
        if app.statusBars.firstMatch.exists {
            app.statusBars.firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        for _ in 0..<2 {
            scrollUpOnePage()
        }
    }

    private func scrollDownOnePage() {
        dragWithinMargin(fromY: 0.88, toY: 0.12)
    }

    private func scrollUpOnePage() {
        dragWithinMargin(fromY: 0.25, toY: 0.88)
    }

    /// Drag inside the editor's left margin. The preview's drag gesture covers
    /// the content and its centre, so a gesture there rotates the head; the
    /// margin is a few points left of the preview and of every slider.
    private func dragWithinMargin(fromY: CGFloat, toY: CGFloat) {
        // Horizontal position comes from the preview, which is always in the
        // editor column, so the drag stays in its left margin on both the
        // single-column iPhone and the split-view iPad. Vertical positions use
        // the window, because a scroll view's frame may report its content.
        let preview = app.descendants(matching: .any)["head-preview"]
        let window = app.frame
        let x = preview.exists ? preview.frame.minX - 8 : editorScrollView.frame.minX + 10
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: window.minY + window.height * fromY))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: window.minY + window.height * toY))
        start.press(forDuration: 0.2, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// The iPad split view contains the sidebar list and the editor. Selecting
    /// the first scroll view would scroll the sidebar, so use the editor's
    /// identifier and fall back to the widest scroll view if it is flattened.
    private var editorScrollView: XCUIElement {
        let named = app.scrollViews["editor-scroll"]
        if named.exists { return named }
        let all = app.scrollViews.allElementsBoundByIndex
        return all.max { $0.frame.width < $1.frame.width } ?? app.scrollViews.firstMatch
    }

    private func returnToProjectList() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == 'Projects' OR label BEGINSWITH 'Back'")
        ).firstMatch
        if back.waitForExistence(timeout: 4) {
            back.tap()
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
        scrollToTop()
        XCTAssertTrue(preview.waitForExistence(timeout: 30),
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

/// A 48×48 luminance sample of the preview plus the fraction of cells that
/// carry the preview's gold colouring. The gold ratio, not raw brightness,
/// proves the head itself drew: the surrounding chrome and a white split-view
/// sidebar are bright but unsaturated, so they cannot satisfy it.
@MainActor
struct PreviewFrame {
    let luminance: [UInt8]
    let goldRatio: Double

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
        var gold = 0
        for index in 0..<(side * side) {
            let r = Double(pixels[index * 4])
            let g = Double(pixels[index * 4 + 1])
            let b = Double(pixels[index * 4 + 2])
            let value = UInt8(min(255, (0.2126 * r + 0.7152 * g + 0.0722 * b).rounded()))
            values[index] = value
            if value >= 45 && r > g && g > b && (r - b) > 25 {
                gold += 1
            }
        }
        self.luminance = values
        self.goldRatio = Double(gold) / Double(side * side)
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
