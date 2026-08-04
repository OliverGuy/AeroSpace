import Common

extension Workspace {
    @MainActor var rootTilingContainer: TilingContainer {
        let containers = children.filterIsInstance(of: TilingContainer.self)
        switch containers.count {
            case 0:
                let orientation: Orientation = switch config.defaultRootContainerOrientation {
                    case .horizontal: .h
                    case .vertical: .v
                    case .auto: workspaceMonitor.then { $0.width >= $0.height } ? .h : .v
                }
                return TilingContainer(parent: self, adaptiveWeight: 1, orientation, config.defaultRootContainerLayout, index: INDEX_BIND_LAST)
            case 1:
                return containers.singleOrNil().orDie()
            default:
                die("Workspace must contain zero or one tiling container as its child")
        }
    }

    @MainActor
    var floatingWindows: [Window] {
        floatingWindowsContainer.children.filterIsInstance(of: Window.self)
    }

    /// Clears `Window.directionalFocusReturn` for every window in the workspace. Any tree
    /// restructuring invalidates the remembered directional-focus targets (e.g. a swap keeps the
    /// source window inside the direction-side subtree, so the read-time validation can't detect the
    /// staleness), so the history must be dropped to avoid focus jumping to the wrong window. Called
    /// from the `bind`/`unbind` choke point — see `resetDirectionalFocusHistoryOnStructuralChange`.
    @MainActor
    func resetDirectionalFocusHistory() {
        for window in allLeafWindowsRecursive {
            window.directionalFocusReturn = [:]
        }
    }

    @MainActor
    var floatingWindowsContainer: FloatingWindowsContainer {
        let containers = children.filterIsInstance(of: FloatingWindowsContainer.self)
        return switch containers.count {
            case 0: FloatingWindowsContainer(parent: self)
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one FloatingWindowsContainer")
        }
    }

    @MainActor var macOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer {
        let containers = children.filterIsInstance(of: MacosFullscreenWindowsContainer.self)
        return switch containers.count {
            case 0: MacosFullscreenWindowsContainer(parent: self)
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one MacosFullscreenWindowsContainer")
        }
    }

    @MainActor var macOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer {
        let containers = children.filterIsInstance(of: MacosHiddenAppsWindowsContainer.self)
        return switch containers.count {
            case 0: MacosHiddenAppsWindowsContainer(parent: self)
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one MacosHiddenAppsWindowsContainer")
        }
    }

    @MainActor var forceAssignedMonitor: MonitorInfo? {
        guard let monitorDescriptions = config.workspaceToMonitorForceAssignment[name] else { return nil }
        let sortedMonitors = sortedMonitorInfos
        return monitorDescriptions.lazy
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .first
    }
}
