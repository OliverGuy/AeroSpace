import AppKit
import Common

struct JoinWithCommand: Command {
    let args: JoinWithCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let currentWindow = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        let joinWithTarget: TreeNode
        if args.byRect {
            guard let leaf = target.workspace.findLeafWindowByRect(from: currentWindow, direction: direction) else {
                return .fail(io.err("No windows in the specified direction"))
            }
            joinWithTarget = leaf
        } else {
            guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
                return .fail(io.err("No windows in the specified direction"))
            }
            joinWithTarget = parent.children[ownIndex + direction.focusOffset]
        }
        guard let targetParent = joinWithTarget.parent as? TilingContainer else { return .fail }
        // The new container is perpendicular to `direction`, so the move direction can't decide the
        // order within it. For --by-rect, order by the windows' rect positions along the new axis;
        // otherwise keep the direction-based default.
        let newAxis = targetParent.orientation.opposite
        let currentBeforeTarget: Bool
        if args.byRect {
            let rects = target.workspace.computeVirtualRects()
            let proj = { (p: CGPoint) in newAxis == .h ? p.x : p.y }
            let src = rects[ObjectIdentifier(currentWindow)]?.center
            let tgt = rects[ObjectIdentifier(joinWithTarget)]?.center
            if let src, let tgt {
                currentBeforeTarget = proj(src) < proj(tgt)
            } else {
                currentBeforeTarget = direction.isPositive
            }
        } else {
            currentBeforeTarget = direction.isPositive
        }
        let prevBinding = joinWithTarget.unbindFromParent()
        let newParent = TilingContainer(
            parent: targetParent,
            adaptiveWeight: prevBinding.adaptiveWeight,
            newAxis,
            .tiles,
            index: prevBinding.index,
        )
        currentWindow.unbindFromParent()

        joinWithTarget.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
        currentWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: currentBeforeTarget ? 0 : INDEX_BIND_LAST)
        return .succ
    }
}
