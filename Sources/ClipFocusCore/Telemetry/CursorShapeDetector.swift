import Foundation
import AppKit

/// Classifies the currently visible macOS system cursor into a `CursorShape`
/// by comparing a tiny visual fingerprint against the standard NSCursor set.
/// Unknown / app-custom cursors fall back to `.arrow`.
public final class CursorShapeDetector {

    private struct Reference {
        let shape: CursorShape
        let feature: [Float]
        let hotspot: CGPoint // normalized 0...1
    }

    private static let gridSize = 16
    /// Maximum fingerprint distance accepted as a match (calibrated against the standard cursor set)
    public var matchThreshold: Float = 0.04

    private lazy var references: [Reference] = buildReferences()

    public init() {}

    /// Detect the shape of the system-wide cursor currently on screen (main thread only).
    public func detectCurrentSystemCursor() -> CursorShape? {
        guard let cursor = NSCursor.currentSystem else { return nil }
        return classify(cursor)
    }

    public func classify(_ cursor: NSCursor) -> CursorShape {
        guard let match = bestMatch(for: cursor) else { return .arrow }
        return match.distance <= matchThreshold ? match.shape : .arrow
    }

    /// Exposed for calibration / diagnostics
    public func bestMatch(for cursor: NSCursor) -> (shape: CursorShape, distance: Float)? {
        guard let feature = Self.fingerprint(cursor.image) else { return nil }
        let hot = Self.normalizedHotspot(cursor)
        var best: (CursorShape, Float)? = nil
        for ref in references {
            var d = Self.distance(feature, ref.feature)
            // Hotspot location is a strong discriminator (arrow tip vs centered shapes)
            let hd = Float(hypot(hot.x - ref.hotspot.x, hot.y - ref.hotspot.y))
            d += hd * 0.25
            if best == nil || d < best!.1 { best = (ref.shape, d) }
        }
        return best
    }

    // MARK: - References

    private func buildReferences() -> [Reference] {
        var pairs: [(CursorShape, NSCursor)] = [
            (.arrow, .arrow),
            (.iBeam, .iBeam),
            (.pointingHand, .pointingHand),
            (.openHand, .openHand),
            (.closedHand, .closedHand),
            (.resizeLeftRight, .resizeLeftRight),
            (.resizeLeftRight, .resizeLeft),
            (.resizeLeftRight, .resizeRight),
            (.resizeUpDown, .resizeUpDown),
            (.resizeUpDown, .resizeUp),
            (.resizeUpDown, .resizeDown),
            (.crosshair, .crosshair),
            (.dragCopy, .dragCopy),
            (.notAllowed, .operationNotAllowed),
            (.arrow, .contextualMenu),
            (.arrow, .dragLink),
            (.arrow, .disappearingItem)
        ]
        pairs.append((.iBeam, .iBeamCursorForVerticalLayout))
        return pairs.compactMap { shape, cursor in
            guard let f = Self.fingerprint(cursor.image) else { return nil }
            return Reference(shape: shape, feature: f, hotspot: Self.normalizedHotspot(cursor))
        }
    }

    // MARK: - Fingerprint

    private static func normalizedHotspot(_ cursor: NSCursor) -> CGPoint {
        let size = cursor.image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: cursor.hotSpot.x / size.width, y: cursor.hotSpot.y / size.height)
    }

    /// 16x16 grid of (alpha, darkness*alpha) — resolution & accessibility-scale independent
    private static func fingerprint(_ image: NSImage) -> [Float]? {
        let n = gridSize
        var rect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        guard rect.width > 0, rect.height > 0,
              let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(
            data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        var feature = [Float](repeating: 0, count: n * n * 2)
        for i in 0..<(n * n) {
            let r = Float(pixels[i * 4]) / 255.0
            let g = Float(pixels[i * 4 + 1]) / 255.0
            let b = Float(pixels[i * 4 + 2]) / 255.0
            let a = Float(pixels[i * 4 + 3]) / 255.0
            let lum = (0.299 * r + 0.587 * g + 0.114 * b) // premultiplied luminance
            feature[i * 2] = a
            feature[i * 2 + 1] = max(0, a - lum) // dark coverage
        }
        return feature
    }

    private static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .greatestFiniteMagnitude }
        var sum: Float = 0
        for i in 0..<a.count { sum += abs(a[i] - b[i]) }
        return sum / Float(a.count)
    }
}
