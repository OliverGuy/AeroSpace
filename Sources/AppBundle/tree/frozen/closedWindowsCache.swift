import AppKit
import Common

/// First line of defence against lock screen
///
/// When you lock the screen, all accessibility API becomes unobservable (all attributes become empty, window id
/// becomes nil, etc.) which tricks AeroSpace into thinking that all windows were closed.
/// That's why every time a window dies AeroSpace caches the "entire world" (unless window is already presented in the cache)
/// so that once the screen is unlocked, AeroSpace could restore windows to where they were
@MainActor private var closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])

struct FrozenMonitor: Sendable, Codable {
    let topLeftCorner: CGPoint
    let visibleWorkspace: String

    @MainActor init(_ monitor: Monitor) {
        topLeftCorner = monitor.rect.topLeftCorner
        visibleWorkspace = monitor.activeWorkspace.name
    }
}

struct FrozenWorkspace: Sendable, Codable {
    let name: String
    let monitor: FrozenMonitor // todo drop this property, once monitor to workspace assignment migrates to TreeNode
    let rootTilingNode: FrozenContainer
    let floatingWindows: [FrozenWindow]
    let macosUnconventionalWindows: [FrozenWindow]

    @MainActor init(_ workspace: Workspace) {
        name = workspace.name
        monitor = FrozenMonitor(workspace.workspaceMonitor)
        rootTilingNode = FrozenContainer(workspace.rootTilingContainer)
        floatingWindows = workspace.floatingWindows.map(FrozenWindow.init)
        macosUnconventionalWindows =
            workspace.macOsNativeHiddenAppsWindowsContainer.children.map { FrozenWindow($0 as! Window) } +
            workspace.macOsNativeFullscreenWindowsContainer.children.map { FrozenWindow($0 as! Window) }
    }
}

@MainActor func cacheClosedWindowIfNeeded() {
    let allWs = Workspace.all
    let allWindowIds = allWs.flatMap { collectAllWindowIdsRecursive($0) }.toSet()
    if allWindowIds.isSubset(of: closedWindowsCache.windowIds) {
        return // already cached
    }
    closedWindowsCache = currentFrozenWorld()
    idRemap = [:]
    allowBundleIdRematch = false // live snapshot: ids are current, no reboot rematch needed
}

@MainActor func currentFrozenWorld() -> FrozenWorld {
    let allWs = Workspace.all
    return FrozenWorld(
        workspaces: allWs.map { FrozenWorkspace($0) },
        monitors: monitors.map(FrozenMonitor.init),
        windowIds: allWs.flatMap { collectAllWindowIdsRecursive($0) }.toSet(),
    )
}

// Persisted so window->workspace assignment and tree layout survive an AeroSpace restart, and, after
// a reboot, so windows can be re-matched to their saved slots by app bundle id (see idRemap below).
// Durable path (survives reboot). Stale ids after a reboot are harmless: the fast path only trusts an
// id match when the bundle id also matches, otherwise it falls back to bundle-id rematch.
private let stateFileUrl: URL = (ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { URL(filePath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/state"))
    .appending(path: "aerospace/tree-state.json")
@MainActor private var lastPersisted: Data? = nil

// Restore state. frozen(old) window id -> live(new) window id. For Ctrl-C/app-restart the mapping is
// identity (ids are stable); after a reboot it's built by matching bundle ids.
@MainActor private var idRemap: [UInt32: UInt32] = [:]
// Bundle-id rematch is only allowed for a cache loaded from disk at startup, never for the in-memory
// lock-screen cache (where a reopened window must NOT hijack a recently-closed window's slot).
@MainActor private var allowBundleIdRematch = false

@MainActor func persistTreeStateToDisk() {
    if !config.restoreTreeOnStartup { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys // stable output so the dedup below actually dedups
    guard let data = try? encoder.encode(currentFrozenWorld()) else { return }
    if data == lastPersisted { return } // ponytail: dedup; add debounce if encode cost ever shows up
    lastPersisted = data
    try? FileManager.default.createDirectory(at: stateFileUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: stateFileUrl, options: .atomic)
}

/// Seed the cache from the previous run's persisted state so that `restoreClosedWindowsCacheIfNeeded`
/// restores windows to their saved workspace/tree position as they're detected at startup.
@MainActor func loadPersistedTreeStateFromDisk() {
    guard let data = try? Data(contentsOf: stateFileUrl),
          let world = try? JSONDecoder().decode(FrozenWorld.self, from: data) else { return }
    lastPersisted = data
    closedWindowsCache = world
    idRemap = [:]
    allowBundleIdRematch = true
}

private func collectFrozenWindows(_ node: FrozenTreeNode) -> [FrozenWindow] {
    switch node {
        case .window(let w): [w]
        case .container(let c): c.children.flatMap(collectFrozenWindows)
    }
}

@MainActor private func allFrozenWindows() -> [FrozenWindow] {
    closedWindowsCache.workspaces.flatMap {
        collectFrozenWindows(.container($0.rootTilingNode)) + $0.floatingWindows + $0.macosUnconventionalWindows
    }
}

@MainActor func restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    let newId = newlyDetectedWindow.windowId
    if idRemap.values.contains(newId) { return true } // already restored (e.g. re-detected after a bundle-id rematch)

    let frozen = allFrozenWindows()
    if let f = frozen.first(where: { $0.id == newId }), f.bundleId == newlyDetectedWindow.app.rawAppBundleId {
        idRemap[newId] = newId // trusted id match (Ctrl-C/app-restart/lock-screen). bundle id guards against cross-reboot id reuse
    } else if allowBundleIdRematch, let bundleId = newlyDetectedWindow.app.rawAppBundleId,
              let oldId = frozen.first(where: { $0.bundleId == bundleId && idRemap[$0.id] == nil })?.id
    {
        idRemap[oldId] = newId // reboot: best-effort match to a saved slot of the same app
    } else {
        return false
    }

    let monitors = monitors
    let topLeftCornerToMonitor = monitors.grouped { $0.rect.topLeftCorner }

    for frozenWorkspace in closedWindowsCache.workspaces {
        let workspace = Workspace.get(byName: frozenWorkspace.name)
        _ = topLeftCornerToMonitor[frozenWorkspace.monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(workspace)
        for frozenWindow in frozenWorkspace.floatingWindows {
            liveMacWindow(forFrozen: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
        }
        for frozenWindow in frozenWorkspace.macosUnconventionalWindows { // Will get fixed by normalizations
            liveMacWindow(forFrozen: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
        }
        let prevRoot = workspace.rootTilingContainer // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
        let potentialOrphans = prevRoot.allLeafWindowsRecursive
        prevRoot.unbindFromParent()
        restoreTreeRecursive(frozenContainer: frozenWorkspace.rootTilingNode, parent: workspace, index: INDEX_BIND_LAST)
        for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
            try await window.relayoutWindow(on: workspace, .cancellable, forceTile: true)
        }
    }

    for monitor in closedWindowsCache.monitors {
        _ = topLeftCornerToMonitor[monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(Workspace.get(byName: monitor.visibleWorkspace))
    }
    return true
}

@MainActor private func liveMacWindow(forFrozen id: UInt32) -> Window? {
    MacWindow.get(byId: idRemap[id] ?? id)
}

@discardableResult
@MainActor
private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: NonLeafTreeNodeObject, index: Int) -> Bool {
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: index,
    )

    for (index, child) in frozenContainer.children.enumerated() {
        switch child {
            case .window(let w):
                // Stop the loop if can't find the window, because otherwise all the subsequent windows will have incorrect index
                guard let window = liveMacWindow(forFrozen: w.id) else { return false }
                window.bind(to: container, adaptiveWeight: w.weight, index: index)
            case .container(let c):
                // There is no reason to continue
                if !restoreTreeRecursive(frozenContainer: c, parent: container, index: index) { return false }
        }
    }
    return true
}

// Consider the following case:
// 1. Close window
// 2. The previous step lead to caching the whole world
// 3. Change something in the layout
// 4. Lock the screen
// 5. The cache won't be updated because all alive windows are already cached
// 6. Unlock the screen
// 7. The wrong cache is used
//
// That's why we have to reset the cache every time layout changes. The layout can only be changed by running commands
// and with mouse manipulations
@MainActor func resetClosedWindowsCache() {
    closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
    idRemap = [:]
    allowBundleIdRematch = false
}
