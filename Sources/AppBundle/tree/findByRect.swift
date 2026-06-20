import AppKit
import Common

extension Workspace {
    /// Find the leaf window in `direction` from `sourceWindow`, picking the descendant whose
    /// rect best overlaps `sourceWindow`'s perpendicular extent at each level. Uses computed
    /// virtual rects derived from the workspace's visible rect and node weights, so it doesn't
    /// depend on a prior layout pass.
    @MainActor
    func findLeafWindowByRect(from sourceWindow: Window, direction: CardinalDirection) -> Window? {
        guard let closest = sourceWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else { return nil }
        let rects = computeVirtualRects()
        guard let sourceRect = rects[ObjectIdentifier(sourceWindow)] else { return nil }
        let siblingTarget = closest.parent.children[closest.ownIndex + direction.focusOffset]
        return findLeafByRect(in: siblingTarget, source: sourceRect, direction: direction, rects: rects)
    }

    @MainActor
    func computeVirtualRects() -> [ObjectIdentifier: Rect] {
        var out: [ObjectIdentifier: Rect] = [:]
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        collectVirtualRects(rootTilingContainer, rect: rect, into: &out)
        return out
    }

    @MainActor
    private func collectVirtualRects(_ node: TreeNode, rect: Rect, into out: inout [ObjectIdentifier: Rect]) {
        out[ObjectIdentifier(node)] = rect
        guard let container = node as? TilingContainer else { return }
        let childRects = container.childVirtualRects(within: rect)
        for (child, childRect) in zip(container.children, childRects) {
            collectVirtualRects(child, rect: childRect, into: &out)
        }
    }
}

extension TilingContainer {
    @MainActor
    func childVirtualRects(within rect: Rect) -> [Rect] {
        if children.isEmpty { return [] }
        if layout == .accordion { return Array(repeating: rect, count: children.count) }
        return rect.sliced(along: orientation, weights: children.map { $0.getWeight(orientation) })
    }
}

@MainActor
private func findLeafByRect(
    in node: TreeNode,
    source: Rect,
    direction: CardinalDirection,
    rects: [ObjectIdentifier: Rect],
) -> Window? {
    switch node.nodeCases {
        case .window(let w): return w
        case .tilingContainer(let c):
            guard !c.children.isEmpty else { return nil }
            // Parallel/accordion containers: enter snapped to direction.opposite (existing convention).
            // Perpendicular containers: pick the child whose perpendicular range best overlaps the source.
            let chosenIndex: Int
            if c.orientation == direction.orientation || c.layout == .accordion {
                chosenIndex = direction.isPositive ? 0 : c.children.count - 1
            } else {
                let perp = direction.orientation.opposite
                chosenIndex = c.children.indices.max(by: { a, b in
                    rangeOverlap(rects[ObjectIdentifier(c.children[a])], source, axis: perp)
                        < rangeOverlap(rects[ObjectIdentifier(c.children[b])], source, axis: perp)
                }) ?? 0
            }
            return findLeafByRect(in: c.children[chosenIndex], source: source, direction: direction, rects: rects)
        case .workspace, .floatingWindowsContainer, .macosMinimizedWindowsContainer,
             .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
            return nil
    }
}

private func rangeOverlap(_ a: Rect?, _ b: Rect, axis: Orientation) -> CGFloat {
    guard let a else { return 0 }
    switch axis {
        case .h: return max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        case .v: return max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }
}
