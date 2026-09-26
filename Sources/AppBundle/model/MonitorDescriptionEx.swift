import Common

extension MonitorDescription {
    @MainActor func resolveMonitor(sortedMonitors: [MonitorInfo]) -> MonitorInfo? {
        switch self {
            case .sequenceNumber(let number): sortedMonitors.getOrNil(atIndex: number - 1)
            case .main: mainMonitorInfo
            case .pattern(let regex): sortedMonitors.first { $0.name.contains(caseInsensitiveRegex: regex) }
            case .secondary:
                sortedMonitors.takeIf { $0.count == 2 }?
                    .first { $0.rect.topLeftCorner != mainMonitorInfo.rect.topLeftCorner }
        }
    }

    /// Whether `monitor` is one of the monitors this description denotes. Unlike
    /// ``resolveMonitor(sortedMonitors:)``, which narrows down to a single monitor, a name pattern
    /// denotes *every* monitor it matches — an exclusion must cover all of them, not just the first.
    @MainActor func matches(_ monitor: MonitorInfo, sortedMonitors: [MonitorInfo]) -> Bool {
        switch self {
            case .pattern(let regex): monitor.name.contains(caseInsensitiveRegex: regex)
            case .main, .secondary, .sequenceNumber:
                resolveMonitor(sortedMonitors: sortedMonitors)?.rect.topLeftCorner == monitor.rect.topLeftCorner
        }
    }
}

extension MonitorInfo {
    /// Excluded monitors are never picked *for* you: no workspace is force-assigned to them, so they
    /// fall back to a fresh unassigned workspace. Explicitly targeting one still works — `focus-monitor
    /// <pattern>`, `move-node-to-monitor` and per-monitor `gaps` all ignore this.
    @MainActor func isExcludedFromWorkspaceAssignment(among sortedMonitors: [MonitorInfo]) -> Bool {
        config.excludeMonitorsFromWorkspaceAssignment
            .contains { $0.matches(self, sortedMonitors: sortedMonitors) }
    }
}
