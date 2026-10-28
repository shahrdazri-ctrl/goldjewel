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
        executionTimeAllowance = 780
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
        revealEditor(preview)
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
        let keyboard = app.keyboards.firstMatch
        if !keyboard.waitForExistence(timeout: 5) {
            nameField.tap()
        }
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10),
                      "\(deviceName): the name field did not take keyboard focus")
        nameField.typeText(" Gate")
        nameField.typeText("\n")
        dismissKeyboard()
        let editedName = nameField.value as? String ?? ""
        XCTAssertTrue(editedName.contains("Gate"),
                      "\(deviceName): typing into the name field produced \(editedName.debugDescription)")
        XCTAssertFalse(app.keyboards.firstMatch.exists,
                       "\(deviceName): keyboard stayed up and would cover the controls")
        step("name edited")

        // Each state is compared with the previous one, which isolates the
        // change made by the switch that was just toggled while halving the
        // number of round trips to the top of the editor.

        // Gallery rail (on by default).
        setToggle("rail-toggle", on: false, preview: preview)
        step("rail off")
        let withoutRail = try capture("02-rail-off", preview: preview)
        assertChanged(withoutRail, from: base, atLeast: 0.005,
                      "switching the gallery off")

        // Prong domes (on by default).
        setToggle("dome-toggle", on: false, preview: preview)
        step("dome off")
        let withoutDome = try capture("03-dome-off", preview: preview)
        assertChanged(withoutDome, from: withoutRail, atLeast: 0.005,
                      "switching the dome off")

        // Bezel (off by default).
        setToggle("bezel-toggle", on: true, preview: preview)
        step("bezel on")
        let withBezel = try capture("04-bezel-on", preview: preview)
        assertChanged(withBezel, from: withoutDome, atLeast: 0.005,
                      "enabling the bezel")

        // Halo (off by default).
        setToggle("halo-toggle", on: true, preview: preview)
        step("halo on")
        let withHalo = try capture("05-halo-on", preview: preview)
        assertChanged(withHalo, from: withBezel, atLeast: 0.005,
                      "enabling the halo")

        // A parameter change that keeps the topology but moves the geometry.
        let gemSlider = app.sliders["gem-diameter"]
        scrollTo(gemSlider)
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
        let afterGem = try capture("06-gem-larger", preview: preview)
        assertChanged(afterGem, from: withHalo, atLeast: 0.01,
                      "moving the gem slider")

        attachFullScreen("12-final")
        step("editing complete")
        app.terminate()

        // Relaunch without the reset switch: the project, its name and the four
        // family switches must come back from projects.json.
        relaunch(reset: false)
        step("relaunched")
        let savedRow = app.descendants(matching: .any)
            .matching(identifier: "project-row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Gate"))
            .firstMatch
        if !savedRow.waitForExistence(timeout: 8) {
            returnToProjectList()
        }
        XCTAssertTrue(savedRow.waitForExistence(timeout: 20),
                      "\(deviceName): the edited project did not survive relaunch")
        savedRow.tap()

        let restoredPreview = app.descendants(matching: .any)["head-preview"]
        XCTAssertTrue(restoredPreview.waitForExistence(timeout: 20),
                      "\(deviceName): restored project has no preview")
        revealEditor(restoredPreview)
        let restored = try capture("13-relaunch", preview: restoredPreview)
        XCTAssertGreaterThan(restored.goldRatio, 0.02,
                             "\(deviceName): restored preview is blank (\(restored.goldRatio) metal pixels)")

        step("restored preview captured")
        let restoredName = app.textFields["project-name"]
        scrollTo(restoredName)
        XCTAssertEqual(restoredName.value as? String ?? "", editedName,
                       "\(deviceName): edited name was not persisted")

        // Rail and dome were left off; bezel and halo were switched on. Both
        // directions must survive the relaunch.
        let persisted: [(String, Bool)] = [
            ("rail-toggle", false),
            ("dome-toggle", false),
            ("bezel-toggle", true),
            ("halo-toggle", true)
        ]
        for (identifier, expected) in persisted {
            let toggle = app.switches[identifier]
            scrollTo(toggle)
            XCTAssertEqual(isOn(toggle), expected,
                           "\(deviceName): \(identifier) was not persisted as \(expected)")
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
        // in case the merged accessibility element spans the whole row. A tap
        // that lands while the overlay sidebar is animating away is swallowed,
        // so retry a bounded number of times and assert the eventual result.
        // Aim at the switch itself, 28 points in from the row's trailing edge.
        // On iPad the row is as wide as the detail column, so a fixed 0.9 lands
        // in the empty gap between the label and the switch and does nothing.
        let rowWidth = toggle.frame.width
        let switchX = rowWidth > 56 ? (rowWidth - 28) / rowWidth : 0.9
        for _ in 0..<3 where isOn(toggle) != on {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: switchX, dy: 0.5)).tap()
            // The switch animates and SwiftUI commits the new state on the next
            // run loop; poll the real value instead of sampling it once.
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline && isOn(toggle) != on {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if isOn(toggle) != on {
                Thread.sleep(forTimeInterval: 0.5)
            }
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

    private func assertChanged(
        _ new: PreviewFrame,
        from old: PreviewFrame,
        atLeast threshold: Double,
        _ action: String
    ) {
        let difference = new.difference(from: old)
        XCTAssertGreaterThan(difference, threshold,
                             "\(deviceName): \(action) changed only \(difference) of the preview")
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
        // Search in half-page steps. A full-page jump can carry a short row
        // (a bare toggle) past the viewport between two hittability checks.
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            dragWithinMargin(fromY: 0.80, toY: 0.34)
        }
        attachFullScreen("scroll-failed")
        XCTFail("\(deviceName): could not scroll to \(element) "
                + "(exists=\(element.exists), hittable=\(element.isHittable), "
                + "frame=\(element.frame), window=\(app.frame))")
    }

    /// Scrolls until the head preview is actually on screen. The status-bar tap
    /// is not reliable on iPad, and the preview is the only element that is
    /// hittable at the top and nowhere else, so it anchors the search instead.
    private func scrollToTop() {
        let preview = app.descendants(matching: .any)["head-preview"]
        for _ in 0..<12 {
            if preview.exists && preview.isHittable {
                // One more pull guarantees the preview's top is inside the
                // viewport rather than merely its centre; at the top this is
                // just the usual bounce.
                dragWithinMargin(fromY: 0.30, toY: 0.72)
                return
            }
            scrollUpOnePage()
        }
    }

    private func scrollUpOnePage() {
        dragWithinMargin(fromY: 0.28, toY: 0.86)
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
        // Stay in the content's right-hand margin. On iPad the left edge
        // belongs to the sidebar reveal gesture, so dragging there opens the
        // overlay instead of scrolling; the preview itself consumes drags to
        // rotate the head. This margin is outside both.
        var x = window.maxX - 14
        if preview.exists && preview.frame.width > 1 {
            x = min(x, preview.frame.maxX + 6)
        }
        x = max(x, window.minX + 12)
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

    /// On iPadOS the sidebar can be presented over the detail, dimming and
    /// swallowing taps. Tapping the dimmed detail dismisses it. iPhone is
    /// already a single column, so this is a no-op there.
    private func revealEditor(_ preview: XCUIElement) {
        guard preview.waitForExistence(timeout: 20) else {
            XCTFail("\(deviceName): editor preview never appeared")
            return
        }
        for _ in 0..<3 where !preview.isHittable {
            let window = app.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.width * 0.92, dy: window.height * 0.5))
                .tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertTrue(preview.isHittable,
                      "\(deviceName): the editor is covered and cannot be reached")
    }

    private func returnToProjectList() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == 'Projects' OR label BEGINSWITH 'Back'")
        ).firstMatch
        if back.waitForExistence(timeout: 4) {
            back.tap()
        } else if UIDevice.current.userInterfaceIdiom != .pad {
            // The navigation bar's leading item is the back button even when
            // its accessibility label differs from the visible title. Never do
            // this on iPad: there the leading item is the New Project button.
            let leading = app.navigationBars.buttons.element(boundBy: 0)
            if leading.exists && leading.isHittable {
                leading.tap()
            }
        }
        // The edge-swipe back gesture is the last fallback on iPhone; on iPad
        // the same gesture opens the sidebar instead of navigating.
        if !app.buttons["new-project"].waitForExistence(timeout: 5),
           UIDevice.current.userInterfaceIdiom != .pad {
            let window = app.frame
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.minX + 2, dy: window.height * 0.5))
            let end = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.width * 0.7, dy: window.height * 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
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
        if !preview.isHittable {
            scrollToTop()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(preview.isHittable,
                      "\(deviceName): preview is not on screen for \(name)")
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
