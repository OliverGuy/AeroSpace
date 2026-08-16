import AppKit
import Common

extension MonitorInfo {
    @MainActor
    var visibleRectPaddedByOuterGaps: Rect {
        let topLeft = visibleRect.topLeftCorner
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: self)
        return Rect(
            topLeftX: topLeft.x + gaps.outer.left.toDouble(),
            topLeftY: topLeft.y + gaps.outer.top.toDouble(),
            width: visibleRect.width - gaps.outer.left.toDouble() - gaps.outer.right.toDouble(),
            height: visibleRect.height - gaps.outer.top.toDouble() - gaps.outer.bottom.toDouble(),
        )
    }

    var monitorId_oneBased: Int? {
        let sorted = sortedMonitorInfos
        let origin = self.rect.topLeftCorner
        return sorted.firstIndex { $0.rect.topLeftCorner == origin }.map { $0 + 1 }
    }

    /// The monitor adjacent to this one in `direction`, or `nil` if this monitor is the last one there.
    func findRelativeMonitor(inDirection direction: CardinalDirection) -> MonitorInfo? {
        findRelativeMonitor(inDirection: direction, among: sortedMonitorInfos)
    }

    /// Where `direction` lands once it runs off the edge of the desktop: the farthest monitor in the
    /// opposite direction. Returns `self` if there is nothing in the opposite direction either.
    func findWrapAroundMonitor(inDirection direction: CardinalDirection) -> MonitorInfo {
        findWrapAroundMonitor(inDirection: direction, among: sortedMonitorInfos)
    }

    /// Monitors never overlap on the desktop, so a monitor lies in `direction` exactly when its range
    /// on that axis starts past ours (touching counts as past). Among those, the closest one wins, and
    /// then the one we share the most edge with — so a monitor sitting under two monitors goes `up` to
    /// whichever of them it overlaps more. Monitors that don't line up with us on the perpendicular
    /// axis at all lose to monitors that do; they are candidates only so that a diagonally placed
    /// monitor stays reachable. Exact ties go to the first monitor in `sortedMonitorInfos`.
    func findRelativeMonitor(inDirection direction: CardinalDirection, among monitors: [MonitorInfo]) -> MonitorInfo? {
        let axis = direction.orientation
        func isInDirection(_ monitor: MonitorInfo) -> Bool {
            direction.isPositive
                ? monitor.rect.getMin(axis) >= rect.getMax(axis)
                : monitor.rect.getMax(axis) <= rect.getMin(axis)
        }
        // Lower is better: lined up beats diagonal, then closest, then widest shared edge, then order
        func rank(_ index: Int, _ monitor: MonitorInfo) -> (Int, CGFloat, CGFloat, Int) {
            let distance = direction.isPositive
                ? monitor.rect.getMin(axis) - rect.getMax(axis)
                : rect.getMin(axis) - monitor.rect.getMax(axis)
            let overlap = rect.overlap(with: monitor.rect, on: axis.opposite)
            return (overlap > 0 ? 0 : 1, distance, -overlap, index)
        }
        return monitors.withIndex
            .filter { $0.value.rect.topLeftCorner != rect.topLeftCorner && isInDirection($0.value) }
            .min { rank($0.index, $0.value) < rank($1.index, $1.value) }?
            .value
    }

    func findWrapAroundMonitor(inDirection direction: CardinalDirection, among monitors: [MonitorInfo]) -> MonitorInfo {
        var monitor: MonitorInfo = self
        // Each step strictly advances against `direction`, so this terminates
        while let next = monitor.findRelativeMonitor(inDirection: direction.opposite, among: monitors) {
            monitor = next
        }
        return monitor
    }
}
