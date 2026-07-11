@testable import AppBundle
import Common
import XCTest

@MainActor
final class FrozenTreePersistenceTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    // The persisted state must survive a JSON round-trip unchanged, otherwise tree layout
    // won't be restored correctly after a restart.
    func testFrozenTreeRoundTrips() throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
            TestWindow.new(id: 3, parent: $0)
        }
        let frozen = FrozenContainer(Workspace.get(byName: name).rootTilingContainer)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(frozen)
        let reEncoded = try encoder.encode(JSONDecoder().decode(FrozenContainer.self, from: encoded))
        assertEquals(encoded, reEncoded)
    }
}
