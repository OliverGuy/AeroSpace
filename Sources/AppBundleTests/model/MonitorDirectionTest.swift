@testable import AppBundle
import Common
import XCTest

/// `monitors` is hardcoded to a single monitor under tests, so these drive the geometry directly
final class MonitorDirectionTest: XCTestCase {
    /// ```
    /// 1 2
    ///  3
    /// ```
    /// 3 straddles the seam between 1 and 2, overlapping neither of them completely
    private let topLeft = TestMonitor(topLeftX: -1920, topLeftY: 0, width: 1920, height: 1080)
    private let topRight = TestMonitor(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
    private let bottom = TestMonitor(topLeftX: -742, topLeftY: 1080, width: 1512, height: 982)

    private var monitors: [MonitorInfo] { [topLeft, bottom, topRight] } // sortedMonitorInfos order (minX, then minY)

    func testDownGoesToTheMonitorBelowFromBothTopMonitors() {
        assertMonitor(topLeft.relative(.down, monitors), bottom)
        assertMonitor(topRight.relative(.down, monitors), bottom)
    }

    /// 3 pokes 770px under 2 and only 742px under 1
    func testUpFromTheBottomMonitorPicksTheMoreOverlappingOfTheTwoAbove() {
        assertMonitor(bottom.relative(.up, monitors), topRight)
    }

    func testExactOverlapTiesFallBackToMonitorOrder() {
        let centered = TestMonitor(topLeftX: -960, topLeftY: 1080, width: 1920, height: 982)
        assertMonitor(centered.relative(.up, [topLeft, centered, topRight]), topLeft)
    }

    func testNoMonitorPastTheOuterFrame() {
        XCTAssertNil(topLeft.relative(.up, monitors))
        XCTAssertNil(topRight.relative(.up, monitors))
        XCTAssertNil(bottom.relative(.down, monitors))
        XCTAssertNil(topLeft.relative(.left, monitors))
        XCTAssertNil(topRight.relative(.right, monitors))
    }

    /// The bottom monitor overlaps both top monitors horizontally, so neither is `left`/`right` of it
    func testHorizontalIgnoresVerticallyDisjointMonitors() {
        assertMonitor(topLeft.relative(.right, monitors), topRight)
        assertMonitor(topRight.relative(.left, monitors), topLeft)
        XCTAssertNil(bottom.relative(.left, monitors))
        XCTAssertNil(bottom.relative(.right, monitors))
    }

    func testWrapAroundGoesToTheFarEnd() {
        assertMonitor(bottom.wrapAround(.down, monitors), topRight)
        assertMonitor(topRight.wrapAround(.up, monitors), bottom)
        assertMonitor(topRight.wrapAround(.right, monitors), topLeft)
        assertMonitor(topLeft.wrapAround(.left, monitors), topRight)
    }

    func testWrapAroundStaysPutWhenThereIsNothingToWrapTo() {
        assertMonitor(bottom.wrapAround(.left, monitors), bottom)
        assertMonitor(topLeft.wrapAround(.up, [topLeft]), topLeft)
    }

    /// A monitor that lines up perpendicularly beats a closer one that doesn't
    func testPrefersAlignedMonitorsOverDiagonalOnes() {
        let current = TestMonitor(topLeftX: 0, topLeftY: 1080, width: 1920, height: 1080)
        let aligned = TestMonitor(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let diagonal = TestMonitor(topLeftX: 1920, topLeftY: 800, width: 1920, height: 280)
        assertMonitor(current.relative(.up, [aligned, current, diagonal]), aligned)
    }

    /// A diagonal monitor is still better than nothing
    func testDiagonalMonitorStaysReachable() {
        let current = TestMonitor(topLeftX: 0, topLeftY: 1080, width: 1920, height: 1080)
        let diagonal = TestMonitor(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080)
        assertMonitor(current.relative(.up, [current, diagonal]), diagonal)
    }

    func testClosestMonitorWinsInAStack() {
        let top = TestMonitor(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let middle = TestMonitor(topLeftX: 0, topLeftY: 1080, width: 1920, height: 1080)
        let bottom = TestMonitor(topLeftX: 0, topLeftY: 2160, width: 1920, height: 1080)
        let stack = [top, middle, bottom]
        assertMonitor(bottom.relative(.up, stack), middle)
        assertMonitor(top.relative(.down, stack), middle)
        assertMonitor(bottom.wrapAround(.down, stack), top)
    }
}

extension MonitorInfo {
    fileprivate func relative(_ direction: CardinalDirection, _ monitors: [MonitorInfo]) -> MonitorInfo? {
        findRelativeMonitor(inDirection: direction, among: monitors)
    }

    fileprivate func wrapAround(_ direction: CardinalDirection, _ monitors: [MonitorInfo]) -> MonitorInfo {
        findWrapAroundMonitor(inDirection: direction, among: monitors)
    }
}

private func assertMonitor(_ actual: MonitorInfo?, _ expected: MonitorInfo, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual?.name, expected.name, file: file, line: line)
}

private struct TestMonitor: MonitorInfo {
    let rect: Rect
    var visibleRect: Rect { rect }
    let name: String
    let monitorAppKitNsScreenScreensId = 1
    let isMain = false
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }

    init(topLeftX: CGFloat, topLeftY: CGFloat, width: CGFloat, height: CGFloat) {
        self.rect = Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width, height: height)
        self.name = "monitor at (\(topLeftX), \(topLeftY))"
    }
}
