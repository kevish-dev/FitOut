import UIKit

/// All positions are in the app window's coordinates, never a moving view's space.
struct FloatingWorkoutGeometry {
    var viewport: CGRect
    var safeArea: UIEdgeInsets
    var size: CGSize
    var obstructions: [CGRect] = []
    var region: CGRect {
        CGRect(x: viewport.minX + safeArea.left + 12, y: viewport.minY + safeArea.top + 64,
            width: max(0, viewport.width - safeArea.left - safeArea.right - 24),
            height: max(0, viewport.height - safeArea.top - safeArea.bottom - 76))
    }
    func preferredCenter(right: Bool, fraction: CGFloat) -> CGPoint {
        CGPoint(x: right ? region.maxX - size.width / 2 : region.minX + size.width / 2,
            y: region.minY + size.height / 2 + min(1, max(0, fraction)) * max(0, region.height - size.height))
    }
    func verticalFraction(for center: CGPoint) -> CGFloat {
        min(1, max(0, (center.y - region.minY - size.height / 2) / max(1, region.height - size.height)))
    }
    func frame(near center: CGPoint) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              region.width >= size.width, region.height >= size.height else { return nil }
        let desired = CGPoint(x: center.x.isFinite ? center.x : region.midX, y: center.y.isFinite ? center.y : region.midY)
        let blocks = obstructions.filter { !$0.isEmpty && !$0.isNull && $0.intersects(viewport) }.map { $0.insetBy(dx: -12, dy: -12) }
        func clamped(_ origin: CGPoint) -> CGRect {
            CGRect(x: min(region.maxX - size.width, max(region.minX, origin.x)),
                y: min(region.maxY - size.height, max(region.minY, origin.y)), width: size.width, height: size.height)
        }
        let proposed = clamped(CGPoint(x: desired.x - size.width / 2, y: desired.y - size.height / 2))
        if !blocks.contains(where: { $0.intersects(proposed) }) { return proposed }
        var candidates = [
            clamped(CGPoint(x: region.minX, y: region.minY)), clamped(CGPoint(x: region.maxX, y: region.minY)),
            clamped(CGPoint(x: region.minX, y: region.maxY)), clamped(CGPoint(x: region.maxX, y: region.maxY))]
        for block in blocks {
            candidates += [clamped(CGPoint(x: proposed.minX, y: block.minY - size.height)),
                clamped(CGPoint(x: proposed.minX, y: block.maxY)),
                clamped(CGPoint(x: block.minX - size.width, y: proposed.minY)),
                clamped(CGPoint(x: block.maxX, y: proposed.minY))]
        }
        func distance(_ frame: CGRect) -> CGFloat { pow(frame.midX - desired.x, 2) + pow(frame.midY - desired.y, 2) }
        return candidates.filter { candidate in !blocks.contains { $0.intersects(candidate) } }.min { distance($0) < distance($1) }
    }
}
