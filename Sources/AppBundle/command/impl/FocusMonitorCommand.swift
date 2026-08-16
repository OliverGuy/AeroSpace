import AppKit
import Common

struct FocusMonitorCommand: Command {
    let args: FocusMonitorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        return switch args.target.val.resolve(target.workspace.workspaceMonitor, wrapAround: args.wrapAround) {
            case .success(let targetMonitor): .from(bool: targetMonitor.activeWorkspace.focusWorkspace())
            case .failure(let msg): .fail(io.err(msg))
        }
    }
}

extension MonitorTarget {
    @MainActor func resolve(_ currentMonitor: MonitorInfo, wrapAround: Bool) -> Result<MonitorInfo, String> {
        switch self {
            case .direction(let direction):
                let targetMonitor = currentMonitor.findRelativeMonitor(inDirection: direction)
                    ?? (wrapAround ? currentMonitor.findWrapAroundMonitor(inDirection: direction) : nil)
                guard let targetMonitor else {
                    return .failure("No monitors in direction \(direction)")
                }
                return .success(targetMonitor)
            case .relative(let nextPrev):
                let monitors = sortedMonitorInfos
                guard let curIndex = monitors.firstIndex(where: { $0.rect.topLeftCorner == currentMonitor.rect.topLeftCorner }) else {
                    return .failure("Can't find current monitor")
                }
                let targetIndex = nextPrev == .next ? curIndex + 1 : curIndex - 1
                let targetMonitor = wrapAround ? monitors.get(wrappingIndex: targetIndex) : monitors.getOrNil(atIndex: targetIndex)
                guard let targetMonitor else {
                    return .failure("Can't find target monitor")
                }
                return .success(targetMonitor)
            case .patterns(let patterns):
                let monitors = sortedMonitorInfos
                guard let targetMonitor = patterns.lazy.compactMap({ $0.resolveMonitor(sortedMonitors: monitors) }).first else {
                    return .failure("None of the monitors match the pattern(s)")
                }
                return .success(targetMonitor)
        }
    }
}
