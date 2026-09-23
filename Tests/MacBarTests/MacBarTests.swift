import XCTest
import AppKit
import ApplicationServices
@testable import MacBar

final class MacBarTests: XCTestCase {
    private let alpha = URL(fileURLWithPath: "/Applications/Alpha.app")
    private let beta = URL(fileURLWithPath: "/Applications/Beta.app")
    private func window(_ title: String, focused: Bool = false, minimized: Bool = false) -> WindowEntry {
        WindowEntry(id: title, title: title, element: AXUIElementCreateApplication(1), minimized: minimized, focused: focused)
    }
    func testGroupedAppHasOneTaskForMultipleWindows() {
        let app = RunningEntry(pid: 1, name: "Alpha", url: alpha, windows: [window("First"), window("Second")], active: true)
        let tasks = TaskLayout.entries(running: [app], pins: [], grouped: true)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].windows.count, 2)
        XCTAssertNil(tasks[0].window)
        XCTAssertTrue(tasks[0].active)
    }
    func testUngroupedMarksOnlyFocusedNonMinimizedWindowActive() {
        let app = RunningEntry(pid: 1, name: "Alpha", url: alpha,
            windows: [window("First", focused: true), window("Second"), window("Third", focused: true, minimized: true)], active: true)
        let tasks = TaskLayout.entries(running: [app], pins: [], grouped: false)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks.map(\.active), [true, false, false])
    }
    func testPinnedOrderSurvivesAppLaunchingAndClosingWithoutDuplicates() {
        let pins = [ApplicationEntry(url: beta, name: "Beta"), ApplicationEntry(url: alpha, name: "Alpha")]
        let app = RunningEntry(pid: 1, name: "Alpha", url: alpha, windows: [], active: false)
        var tasks = TaskLayout.entries(running: [app], pins: pins, grouped: true)
        XCTAssertEqual(tasks.map(\.url), [beta, alpha])
        XCTAssertEqual(tasks.map(\.running), [false, true])
        tasks = TaskLayout.entries(running: [], pins: pins, grouped: true)
        XCTAssertEqual(tasks.map(\.url), [beta, alpha])
        XCTAssertEqual(tasks.map(\.running), [false, false])
    }
    func testNoPermissionStillProducesAppTasks() {
        let app = RunningEntry(pid: 1, name: "Alpha", url: alpha, windows: [], active: true)
        XCTAssertEqual(TaskLayout.entries(running: [app], pins: [], grouped: false, windowsAccessible: false).count, 1)
    }
    func testFrameRespectsDockAndSecondaryScreenOrigin() {
        let screen = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let visible = NSRect(x: -1920, y: -120, width: 1920, height: 980)
        let frame = TaskLayout.frame(screen: screen, visible: visible)
        XCTAssertEqual(frame.minY, -120)
        XCTAssertEqual(frame.minX, -1920)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertTrue(visible.contains(frame))
    }
    func testSearchIgnoresCaseAccentsAndSurroundingWhitespace() {
        let entries = [ApplicationEntry(url: alpha, name: "Café Alpha"), ApplicationEntry(url: beta, name: "Beta")]
        XCTAssertEqual(ApplicationCatalog.filter(entries, query: "  CAFE alpha ").map(\.url), [alpha])
        XCTAssertEqual(ApplicationCatalog.filter(entries, query: " ").count, 2)
        XCTAssertTrue(ApplicationCatalog.filter(entries, query: "absent").isEmpty)
    }
    func testGroupingDefaultsToWindows11StyleAndPersists() {
        let suite = "MacBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.grouped)
        preferences.grouped = false
        XCTAssertFalse(Preferences(defaults: defaults).grouped)
    }
}
