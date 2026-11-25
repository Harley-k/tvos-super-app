import Foundation
import XCTest

final class MacImportPlaybackTests: XCTestCase {
    @MainActor
    func testImportFromFormPersistAndPlayInApp() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SUPERTV_UI_TEST_SUITE"] = "SuperTV.UI.\(UUID().uuidString)"
        func item(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        func click(_ id: String) {
            let control = item(id)
            XCTAssertTrue(control.waitForExistence(timeout: 12), "Missing \(id)")
            control.click()
        }
        app.launch()
        click("source-import")
        click("source-fill-example")
        let field = item("source-url")
        let address = try XCTUnwrap(field.value as? String)
        let url = try XCTUnwrap(URL(string: address))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host?.lowercased(), "raw.githubusercontent.com")
        let hash = address.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        let row = "show-link-" + String(hash, radix: 16)
        click("source-import-submit")
        XCTAssertTrue(item(row).waitForExistence(timeout: 12))
        app.terminate(); app.launch()
        click(row)
        click("episode-media")
        assertPlaybackAdvances(item("playback-progress"))
    }

    @MainActor
    func testBundledOpenFilmPlaysInApp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SUPERTV_UI_TEST_SUITE"] = "SuperTV.UI.\(UUID().uuidString)"
        app.launch()
        for id in ["show-public-wing-it", "episode-wing-it-1"] {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 12), "Missing \(id)")
            element.click()
        }
        assertPlaybackAdvances(app.descendants(matching: .any).matching(identifier: "playback-progress").firstMatch)
    }


    @MainActor
    func testManagedSourcesRefreshAndAllThreeOpenFilmsPlay() throws {
        continueAfterFailure = false
        // A fresh suite for each title avoids confusing a previous player's time with this one.
        for (index, id) in ["big-buck-bunny", "spring", "sintel"].enumerated() {
            let app = XCUIApplication()
            app.launchEnvironment["SUPERTV_UI_TEST_SUITE"] = "SuperTV.UI.\(UUID().uuidString)"
            app.launchEnvironment["SUPERTV_UI_SKIP_AUTO_SOURCE_REFRESH"] = "1"
            func item(_ name: String) -> XCUIElement {
                app.descendants(matching: .any).matching(identifier: name).firstMatch
            }
            func click(_ name: String) {
                let view = item(name)
                XCTAssertTrue(view.waitForExistence(timeout: 12), "Missing \(name)")
                view.click()
            }
            app.launch()
            click("source-directory")
            if index == 0 {
                click("source-directory-refresh")
                let state = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label CONTAINS %@", "已刷新"), object: item("source-directory-status"))
                XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 18), .completed)
            }
            click("source-managed-" + id)
            click("episode-feature")
            assertPlaybackAdvances(item("playback-progress"))
            app.terminate()
        }
    }

    @MainActor
    private func assertPlaybackAdvances(_ clock: XCUIElement) {
        XCTAssertTrue(clock.waitForExistence(timeout: 15))
        let limit = Date().addingTimeInterval(40)
        var first: Double?
        var latest: Double?
        repeat {
            let texts = [clock.value as? String, Optional(clock.label)].compactMap { $0 }
            if let time = texts.compactMap({ Double($0) }).first {
                if first == nil { first = time }
                latest = time
                if let first, time >= first + 2 { return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < limit
        XCTFail("Playback did not advance: \(String(describing: first)) → \(String(describing: latest))")
    }
}
