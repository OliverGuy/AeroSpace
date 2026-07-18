@testable import AppBundle
import Common
import XCTest

@MainActor
final class JoinWithCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testJoinWith_byRect() async {
        // h_tiles [v_tiles[A=1, B=2(focused)], v_tiles[C=3, D=4]]
        // join-with right --by-rect targets D (bottom-right), so B joins with D.
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 3, parent: $0)
                TestWindow.new(id: 4, parent: $0)
            }
        }

        await parseCommand("join-with --by-rect right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .v_tiles([.window(1)]),
                .v_tiles([
                    .window(3),
                    .h_tiles([.window(2), .window(4)]),
                ]),
            ]),
        )
    }

    func testMoveIn() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await parseCommand("join-with right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([
                .window(1),
                .window(2),
            ]),
        ]))
    }
}
