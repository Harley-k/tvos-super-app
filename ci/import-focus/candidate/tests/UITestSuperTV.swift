import Foundation
import XCTest

/// Runs on a tvOS simulator with actual Siri Remote input and the original offline fixtures.
/// UI progress is read from the app's AVPlayer-derived current-time accessibility value.
final class SuperTVUITests: XCTestCase {
    @MainActor
    func testOfflinePlaybackAdvancesResumesAndDoesNotLeakIntoOtherEpisode() throws {
        let app = startCleanApp()
        try choose("show-demo-bip-bop", in: app)
        try choose("episode-demo-1", in: app)

        let progress = element("playback-progress", in: app)
        let initial = try waitForSeconds(progress, timeout: 8, where: { (0..<4).contains($0) })
        let advanced = try waitForSeconds(progress, timeout: 15, where: { $0 >= 7 })
        XCTAssertGreaterThan(advanced, initial + 4, "播放时钟没有真实向前推进")
        try choose("playback-exit", in: app, timeout: 5)

        let resume = element("resume-demo-1", in: app)
        let saved = try waitForSeconds(resume, timeout: 5, where: { $0 >= 6 })
        XCTAssertGreaterThan(saved, 5)
        XCTAssertFalse(element("resume-demo-2", in: app).exists, "另一集不应获得第 1 集的播放进度")
        // Restart the app so the test exercises persistent storage, not a view's in-memory state.
        app.terminate()
        app.launch()
        try choose("show-demo-bip-bop", in: app)
        let reloaded = try waitForSeconds(element("resume-demo-1", in: app), timeout: 5, where: { $0 >= 6 })
        XCTAssertEqual(reloaded, saved, accuracy: 1)
        try choose("episode-demo-1", in: app)
        // A full five seconds from zero still cannot meet this threshold.
        let resumed = try waitForSeconds(element("playback-progress", in: app), timeout: 5,
                                         where: { $0 >= saved - 1 && $0 <= saved + 5 })
        XCTAssertGreaterThanOrEqual(resumed, saved - 1)
        try choose("playback-exit", in: app, timeout: 5)

        try choose("episode-demo-2", in: app)
        let second = try waitForSeconds(element("playback-progress", in: app), timeout: 5,
                                        where: { (0.25..<4).contains($0) })
        XCTAssertLessThan(second, saved - 2, "第 2 集错误地从第 1 集的保存位置开始播放")
    }

    @MainActor
    func testEmptySourceReportsErrorAndKeepsImportUsable() throws {
        let app = startCleanApp()
        try choose("source-import", in: app)
        let input = element("source-url", in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        try choose("source-import-submit", in: app)
        let error = element("source-error", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 5), "空来源须出现独立的校验错误")
        XCTAssertTrue(input.exists, "显示校验错误后仍应能修改来源")
        XCTAssertTrue(element("source-import-submit", in: app).exists)

        // Validation must not strand the remote on the submit row; no taps or direct app calls.
        try focus("source-url", in: app)
        XCTAssertTrue(input.hasFocus, "报告错误后，方向键必须能回到地址输入")
        try focus("source-import-submit", in: app)
        XCTAssertTrue(element("source-import-submit", in: app).hasFocus, "改完地址后必须能用方向键回到导入")
    }

    @MainActor
    func testMissingMediaShowsRecoverablePlaybackFailure() throws {
        let app = startCleanApp(badMedia: true)
        try choose("show-ui-missing-media", in: app)
        try choose("episode-ui-missing-media-first", in: app)
        XCTAssertTrue(element("playback-error", in: app).waitForExistence(timeout: 20),
                      "AVPlayer 失败或超时应显式可见")
        try choose("playback-exit", in: app)
        XCTAssertTrue(element("episode-ui-missing-media-first", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func startCleanApp(badMedia: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SUPERTV_UI_TEST_SUITE"] = "SuperTV.UI.\(UUID().uuidString)"
        if badMedia { app.launchEnvironment["SUPERTV_UI_BAD_MEDIA"] = "1" }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func choose(_ id: String, in app: XCUIApplication, timeout: TimeInterval = 8) throws {
        try focus(id, in: app, timeout: timeout)
        XCUIRemote.shared.press(.select)
    }

    @MainActor
    private func focus(_ id: String, in app: XCUIApplication, timeout: TimeInterval = 8) throws {
        let target = element(id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "没有找到控件: \(id)")
        let remote = XCUIRemote.shared
        let deadline = Date().addingTimeInterval(timeout)
        let fallback: [XCUIRemote.Button] = [.down, .right, .up, .left]
        var triedDirection: [String: Int] = [:]
        var move = 0
        while !target.hasFocus && Date() < deadline && move < 12 {
            let focused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == TRUE")).allElementsBoundByIndex
                .filter { !$0.frame.isEmpty }
                .min { a, b in a.frame.width * a.frame.height < b.frame.width * b.frame.height }
            var direction = fallback[move % fallback.count]
            if let focused {
                let dx = target.frame.midX - focused.frame.midX
                let dy = target.frame.midY - focused.frame.midY
                if abs(dy) > abs(dx) / 2 && abs(dy) > 8 {
                    direction = dy > 0 ? .down : .up
                } else if abs(dx) > 8 {
                    direction = dx > 0 ? .right : .left
                }
                let state = "\(focused.identifier):\(focused.frame.midX):\(focused.frame.midY):\(direction)"
                if (triedDirection[state] ?? 0) > 0 {
                    direction = fallback[move % fallback.count]
                }
                triedDirection[state, default: 0] += 1
            }
            move += 1
            remote.press(direction)
        }
        XCTAssertTrue(target.hasFocus, "遥控器无法聚焦到 \(id)")
        guard target.hasFocus else { throw ProbeFailure.focus }
    }

    @MainActor
    private func waitForSeconds(_ element: XCUIElement, timeout: TimeInterval,
                                where predicate: (Double) -> Bool) throws -> Double {
        let end = Date().addingTimeInterval(timeout)
        var lastValue: Double?
        while Date() < end {
            if element.exists, let seconds = rawSeconds(element) {
                lastValue = seconds
                if predicate(seconds) { return seconds }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.17))
        }
        XCTFail("\(element.identifier) 的实际时间未满足条件，最后值：\(String(describing: lastValue))")
        throw ProbeFailure.progress
    }

    @MainActor
    private func rawSeconds(_ element: XCUIElement) -> Double? {
        let values = [element.value as? String, element.label]
        for candidate in values.compactMap({ $0 }) {
            if let seconds = Double(candidate.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return seconds
            }
            if let span = candidate.range(of: #"[0-9]+:[0-9]{2}"#, options: .regularExpression) {
                let parts = candidate[span].split(separator: ":").compactMap { Int($0) }
                if parts.count == 2 { return Double(parts[0] * 60 + parts[1]) }
            }
        }
        return nil
    }

    private enum ProbeFailure: Error { case focus, progress }
}
