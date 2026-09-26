@testable import AppBundle
import Common
import XCTest

@MainActor
final class ExcludeMonitorsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private let dell = TestMonitor(topLeftX: -1920, topLeftY: 0, width: 1920, height: 1080, name: "DELL S2725QC")
    private let builtIn = TestMonitor(topLeftX: -742, topLeftY: 1080, width: 1512, height: 982, name: "Built-in Retina Display")
    private let publicTv = TestMonitor(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080, name: "Public Conference TV")

    private var monitors: [MonitorInfo] { [dell, builtIn, publicTv] } // sortedMonitorInfos order (minX, then minY)

    private func assign(_ workspace: String, _ descriptions: MonitorDescription...) {
        config.workspaceToMonitorForceAssignment[workspace] = descriptions
    }

    private func exclude(_ descriptions: MonitorDescription...) {
        config.excludeMonitorsFromWorkspaceAssignment = descriptions
    }

    private func assigned(_ workspace: String) -> String? {
        Workspace.get(byName: workspace).forceAssignedMonitor(among: monitors)?.name
    }

    func testWithoutExclusionsTheFirstMatchingDescriptionWins() {
        assign("1", .pattern("dell")!)
        assign("2", .pattern("public")!)
        assign("3", .pattern("nonexistent")!, .pattern("built-in")!)
        assertEquals(assigned("1"), dell.name)
        assertEquals(assigned("2"), publicTv.name)
        assertEquals(assigned("3"), builtIn.name)
    }

    func testExcludedMonitorIsSkippedInFavourOfTheNextDescription() {
        exclude(.pattern("public")!)
        assign("1", .pattern("public")!, .pattern("built-in")!)
        assertEquals(assigned("1"), builtIn.name)
    }

    /// A pattern denotes every monitor it matches, so exclusion has to look past the first one
    func testExcludedMonitorIsSkippedInFavourOfTheNextMatchOfTheSamePattern() {
        exclude(.pattern("public")!)
        assign("1", .pattern("s2725qc|conference")!)
        assertEquals(assigned("1"), dell.name)
    }

    func testChainThatOnlyNamesExcludedMonitorsPinsToTheFirstAllowedMonitor() {
        exclude(.pattern("public")!)
        assign("1", .pattern("public")!)
        assertEquals(assigned("1"), dell.name)
    }

    /// Distinct from the case above: nothing matched, so the workspace is free to go anywhere
    func testChainThatNamesNoConnectedMonitorStaysUnassigned() {
        exclude(.pattern("public")!)
        assign("1", .pattern("nonexistent")!)
        XCTAssertNil(assigned("1"))
    }

    func testUnlistedWorkspaceStaysUnassigned() {
        exclude(.pattern("public")!)
        XCTAssertNil(assigned("G"))
    }

    func testSequenceNumbersKeepCountingExcludedMonitors() {
        exclude(.pattern("dell")!)
        assign("1", .sequenceNumber(2)) // built-in, still 2nd even though the 1st is excluded
        assertEquals(assigned("1"), builtIn.name)
    }

    func testExcludingBySequenceNumber() {
        exclude(.sequenceNumber(1))
        assign("1", .sequenceNumber(1), .pattern("built-in")!)
        assertEquals(assigned("1"), builtIn.name)
    }

    func testExcludingEveryMonitorLeavesAssignmentsUnresolvable() {
        exclude(.pattern("dell")!, .pattern("built-in")!, .pattern("public")!)
        assign("1", .pattern("dell")!)
        XCTAssertNil(assigned("1"))
    }

    /// What makes an excluded monitor fall back to a fresh workspace: `getStubWorkspace` skips every
    /// workspace that is assigned to a different monitor, so if none of them resolve here it keeps
    /// scanning past the assigned range
    func testNoWorkspaceIsEverForceAssignedToAnExcludedMonitor() {
        exclude(.pattern("public")!)
        for i in 1 ... 30 { assign(String(i), .pattern("public")!) }
        for i in 1 ... 30 { XCTAssertNotEqual(assigned(String(i)), publicTv.name) }
    }

    func testParse() {
        let result = parseConfig("exclude-monitors-from-workspace-assignment = ['public', 2]")
        assertEquals(result.config.excludeMonitorsFromWorkspaceAssignment, [.pattern("public")!, .sequenceNumber(2)])
        assertEquals(result.strErrors, [])
        assertEquals(defaultConfig.excludeMonitorsFromWorkspaceAssignment, [])
    }

    func testParseSingleValueWithoutAnArray() {
        assertEquals(
            parseConfig("exclude-monitors-from-workspace-assignment = 'public'").config.excludeMonitorsFromWorkspaceAssignment,
            [.pattern("public")!],
        )
    }

    func testParseError() {
        assertEquals(
            parseConfig("exclude-monitors-from-workspace-assignment = [0]").strErrors,
            ["[ERROR] exclude-monitors-from-workspace-assignment[0]: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal"],
        )
    }
}
