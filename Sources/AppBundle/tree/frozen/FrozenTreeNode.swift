import AppKit
import Common

enum FrozenTreeNode: Sendable, Codable {
    case container(FrozenContainer)
    case window(FrozenWindow)
}

struct FrozenContainer: Sendable, Codable {
    let children: [FrozenTreeNode]
    let layout: Layout
    let orientation: Orientation
    let weight: CGFloat

    @MainActor init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0.nodeCases {
                case .window(let w): .window(FrozenWindow(w))
                case .tilingContainer(let c): .container(FrozenContainer(c))
                case .workspace,
                     .floatingWindowsContainer,
                     .macosMinimizedWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosPopupWindowsContainer:
                    illegalChildParentRelation(child: $0, parent: container)
            }
        }
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
    }
}

struct FrozenWindow: Sendable, Codable {
    let id: UInt32
    let weight: CGFloat
    let bundleId: String? // Used to re-match windows after a reboot, when window ids are no longer stable

    @MainActor init(_ window: Window) {
        id = window.windowId
        weight = getWeightOrNil(window) ?? 1
        bundleId = window.app.rawAppBundleId
    }
}

@MainActor private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}
