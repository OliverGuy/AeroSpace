@testable import AppBundle
import Common
import XCTest

// todo write tests
//
// test 1
//     horizontal
//         window1
//         vertical
//             vertical
//                 window2 <-- focused
//             vertical
//                 window5
//                 horizontal
//                     window3
//                     window4
// pre-condition: focus_wrapping force_workspace
// action: focus up
// expected: mru(window3, window4) is focused

@MainActor
final class FocusCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        XCTAssertTrue(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values") == true)
        var expected = FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.left))
        expected.rawBoundaries = .workspace
        testParseSingleCommandSucc("focus --boundaries workspace left", expected)

        assertEquals(
            parseCommand("focus --boundaries workspace --boundaries workspace left").errorOrNil,
            "ERROR: Duplicated option '--boundaries'",
        )
        assertEquals(
            parseCommand("focus --window-id 42 --ignore-floating").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus --boundaries all-monitors-outer-frame dfs-next").errorOrNil,
            "(dfs-next|dfs-prev) only supports --boundaries workspace",
        )

        assertEquals(
            parseCommand("focus --window-id 42 --wrap-around").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus left --boundaries-action wrap-around-the-workspace --wrap-around").errorOrNil,
            "ERROR: Conflicting options: --boundaries-action, --wrap-around",
        )
        assertEquals(
            parseCommand("focus dfs-next --fail-if-fullscreen").errorOrNil,
            "--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument",
        )
        assertEquals(
            parseCommand("focus --fail-if-macos-native-fullscreen --window-id 42").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertNil(parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen left").errorOrNil)
    }

    func testFailIfFullscreen() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isFullscreen = true
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFailIfMacosNativeFullscreen() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isMacosFullscreenForTest = true

            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFailIfFullscreenAllowsRegularWindows() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocus_byRect() async throws {
        // h_tiles [v_tiles[A=1, B=2(focused)], v_tiles[C=3, D=4]]
        // focus right --by-rect should focus D (bottom-right), even if C is MRU.
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 3, parent: $0)
                TestWindow.new(id: 4, parent: $0)
            }
        }
        Workspace.get(byName: name).rootTilingContainer.children
            .compactMap { ($0 as? TilingContainer)?.children.first as? Window }
            .first(where: { $0.windowId == 3 })?
            .markAsMostRecentChild()

        try await parseCommand("focus --by-rect right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)
    }

    func testFocus_directionalFocusHistory() async throws {
        // h_tiles [A=1, v_tiles[B=2, C=3(focused)]]
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0)
                assertEquals(TestWindow.new(id: 3, parent: $0).focusWindow(), true)
            }
        }

        try await parseCommand("focus --by-rect --directional-focus-history left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1) // moved onto A
        // Without history, --by-rect right from A focuses B (top). With history, it returns to C.
        try await parseCommand("focus --by-rect --directional-focus-history right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
    }

    func testFocus_directionalFocusHistory_invalidatedByLayoutChange() async throws {
        // h_tiles [A=1, v_tiles[B=2, C=3(focused)]]
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0)
                assertEquals(TestWindow.new(id: 3, parent: $0).focusWindow(), true)
            }
        }
        try await parseCommand("focus --by-rect --directional-focus-history left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1) // on A, remembers right -> C

        // Move C to the LEFT of A: it's no longer in the right subtree, so the memory is stale.
        let c = Window.get(byId: 3)!
        c.unbindFromParent()
        c.bind(to: root, adaptiveWeight: 1, index: 0)

        try await parseCommand("focus --by-rect --directional-focus-history right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2) // falls back to rect-best (B), not stale C
    }

    func testFocus_directionalFocusHistory_resetByMove() async {
        // 2x2 grid: h_tiles[ v_tiles[A=1, C=3], v_tiles[B=2, D=4] ]
        //   A B
        //   C D
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 4, parent: $0)
            }
        }

        // From B, focus left onto A: A now remembers "go right -> B".
        await parseCommand("focus --by-rect --directional-focus-history left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)

        // Swap B and D (move D up). Now:
        //   A D
        //   C B
        // B stays inside the right subtree, so the read-time validation can't spot the staleness.
        assertEquals(Window.get(byId: 4)!.focusWindow(), true)
        await parseCommand("move up").cmdOrDie.run(.defaultEnv, .emptyStdin)

        // Focus right from A must follow the current layout (D, top-right), not the stale history (B).
        assertEquals(Window.get(byId: 1)!.focusWindow(), true)
        await parseCommand("focus --by-rect --directional-focus-history right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)
    }

    /// After recording directional-focus history on A ("go right -> B"), performs `event` and
    /// asserts the history was dropped. Covers non-`move` restructuring: spawns, closures, etc.
    @MainActor
    private func assertHistoryResetBy(_ event: (_ rightColumn: TilingContainer) -> Void) async {
        // h_tiles[ v_tiles[A=1, C=3], v_tiles[B=2, D=4] ]
        var rightColumn: TilingContainer! = nil
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }
            rightColumn = TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 4, parent: $0)
            }
        }
        await parseCommand("focus --by-rect --directional-focus-history left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let a = Window.get(byId: 1)!
        assertEquals(a.directionalFocusReturn[.right], 2) // precondition: history recorded

        event(rightColumn)

        assertEquals(a.directionalFocusReturn.isEmpty, true) // history dropped by the restructuring
    }

    func testFocus_directionalFocusHistory_resetBySpawn() async {
        await assertHistoryResetBy { rightColumn in
            TestWindow.new(id: 5, parent: rightColumn) // a new window appears
        }
    }

    func testFocus_directionalFocusHistory_resetByClosure() async {
        await assertHistoryResetBy { _ in
            Window.get(byId: 4)!.closeAxWindow() // a window is closed (non-AeroSpace event)
        }
    }

    func testFocus() {
        assertEquals(focus.windowOrNil, nil)
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusOverFloatingWindows() async {
        assertEquals(focus.windowOrNil, nil)
        Workspace.get(byName: name).floatingWindowsContainer.apply {
            TestWindow.new(id: 1, parent: $0, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
            assertEquals(TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100)).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
    }

    func testFocusAlongTheContainerOrientation() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusAcrossTheContainerOrientation() async {
        Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
            TestWindow.new(id: 2, parent: $0.rootTilingContainer)
            assertEquals($0.focusWorkspace(), true)
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusNoWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus --boundaries workspace --boundaries-action wrap-around-the-workspace left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusFindMruLeaf() async {
        let workspace = Workspace.get(byName: name)
        var startWindow: Window!
        var window2: Window!
        var window3: Window!
        var unrelatedWindow: Window!
        workspace.rootTilingContainer.apply {
            startWindow = TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    window2 = TestWindow.new(id: 2, parent: $0)
                    unrelatedWindow = TestWindow.new(id: 5, parent: $0)
                }
                window3 = TestWindow.new(id: 3, parent: $0)
            }
        }

        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3) // The latest bound
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        window2.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)

        window3.markAsMostRecentChild()
        unrelatedWindow.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusOutsideOfTheContainer() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusOutsideOfTheContainer2() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusDfsRelative() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    TestWindow.new(id: 3, parent: $0)
                }
            }
            TestWindow.new(id: 4, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)

        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)

        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusDfsRelativeWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action stop dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action fail dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action stop dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action fail dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }
}
