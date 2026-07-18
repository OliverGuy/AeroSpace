@testable import AppBundle
import Common
import XCTest

@MainActor
final class OnWindowDetectedTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSplitNewWindowWithFocused() async throws {
        config.splitNewWindowWithFocused = true
        defer { config.splitNewWindowWithFocused = false }
        let workspace = Workspace.get(byName: name)
        let focused = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(focused.focusWindow(), true)
        let new = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        try await new.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)
        // The new window is wrapped together with the focused one in a fresh perpendicular container.
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([.v_tiles([.window(1), .window(2)])]),
        )
    }

    func testMatcherCommandReceivesDetectedWindowId() async {
        let workspace = Workspace.get(byName: name)
        let focused = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let detected = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        assertEquals(focused.focusWindow(), true)
        assertEquals(focus.windowOrNil?.windowId, 1)

        let callback = WindowDetectedCallback(
            matcher: .command(parseCommand("test %{window-id} = 2").cmdOrDie),
            rawRun: .empty,
        )

        assertEquals(await callback.matches(detected), true)
        assertEquals(await callback.matches(focused), false)
    }

    func testRunCommandReceivesDetectedWindowIdInEnv() async {
        let workspaceA = Workspace.get(byName: "a")
        let focused = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        let detected = TestWindow.new(id: 2, parent: workspaceA.rootTilingContainer)
        assertEquals(focused.focusWindow(), true)
        assertEquals(focus.windowOrNil?.windowId, 1)

        config.onWindowDetected = [
            WindowDetectedCallback(
                matcher: .command(.empty), // true
                rawRun: parseCommand("move-node-to-workspace b").cmdOrDie,
            ),
        ]

        await tryOnWindowDetected(detected) // todo: tryOnWindowDetected must not be called manually in tests

        assertEquals((Workspace.get(byName: "b").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 2)
        assertEquals((workspaceA.rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }
}
