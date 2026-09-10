import Foundation
import CoreGraphics
import CoreImage
#if canImport(AppKit)
import AppKit
#endif

/// High-Definition Mathematical Vector Cursor Engine
/// Renders crisp, scalable, non-pixelated custom cursors (Arrow, I-Beam, Hand, Grab)
/// with press squash effects and animated shockwave click ripples.
public final class CustomCursorRenderer: Sendable {
    public static let shared = CustomCursorRenderer()
    
    public init() {}
    
    // MARK: - Hotspot Offsets (Relative to cursor bounding box)
    
    public static func hotspot(for type: CursorType, size: CGFloat) -> CGPoint {
        switch type {
        case .arrow:
            return CGPoint(x: 1.0, y: 1.0)
        case .iBeam:
            return CGPoint(x: size * (10.0 / 24.0), y: size * (12.0 / 24.0))
        case .pointingHand:
            return CGPoint(x: size * (8.5 / 24.0), y: 1.5)
        case .openHand, .closedHand:
            return CGPoint(x: size * 0.45, y: size * 0.45)
        }
    }
    
    // MARK: - Vector Path Generation
    
    /// Generates iconic macOS / Screen Studio style clean white arrow cursor
    public static func createModernArrowPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 24.0
        
        path.move(to: CGPoint(x: 1.0 * s, y: 1.0 * s))
        path.addLine(to: CGPoint(x: 1.0 * s, y: 20.0 * s))
        path.addLine(to: CGPoint(x: 5.8 * s, y: 15.6 * s))
        path.addLine(to: CGPoint(x: 10.2 * s, y: 23.5 * s))
        path.addLine(to: CGPoint(x: 13.8 * s, y: 21.5 * s))
        path.addLine(to: CGPoint(x: 9.4 * s, y: 13.8 * s))
        path.addLine(to: CGPoint(x: 15.6 * s, y: 13.8 * s))
        path.closeSubpath()
        
        return path
    }
    
    /// Generates closed, high-contrast I-Beam text selection cursor
    public static func createIBeamPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 24.0
        let cx = 10.0 * s
        let top = 2.0 * s
        let bottom = 22.0 * s
        let serifHalf = 4.8 * s
        let barHalf = 1.3 * s
        
        path.move(to: CGPoint(x: cx - serifHalf, y: top))
        path.addLine(to: CGPoint(x: cx + serifHalf, y: top))
        path.addLine(to: CGPoint(x: cx + serifHalf, y: top + 2.0 * s))
        path.addLine(to: CGPoint(x: cx + barHalf, y: top + 2.0 * s))
        path.addLine(to: CGPoint(x: cx + barHalf, y: bottom - 2.0 * s))
        path.addLine(to: CGPoint(x: cx + serifHalf, y: bottom - 2.0 * s))
        path.addLine(to: CGPoint(x: cx + serifHalf, y: bottom))
        path.addLine(to: CGPoint(x: cx - serifHalf, y: bottom))
        path.addLine(to: CGPoint(x: cx - serifHalf, y: bottom - 2.0 * s))
        path.addLine(to: CGPoint(x: cx - barHalf, y: bottom - 2.0 * s))
        path.addLine(to: CGPoint(x: cx - barHalf, y: top + 2.0 * s))
        path.addLine(to: CGPoint(x: cx - serifHalf, y: top + 2.0 * s))
        path.closeSubpath()
        
        return path
    }
    
    /// Generates clean white pointing hand cursor
    public static func createPointingHandPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 24.0
        
        path.move(to: CGPoint(x: 7.0 * s, y: 1.5 * s))
        path.addLine(to: CGPoint(x: 10.0 * s, y: 1.5 * s))
        path.addLine(to: CGPoint(x: 10.0 * s, y: 9.0 * s))
        path.addLine(to: CGPoint(x: 13.0 * s, y: 9.0 * s))
        path.addLine(to: CGPoint(x: 13.0 * s, y: 11.5 * s))
        path.addLine(to: CGPoint(x: 16.0 * s, y: 11.5 * s))
        path.addLine(to: CGPoint(x: 16.0 * s, y: 14.0 * s))
        path.addLine(to: CGPoint(x: 18.5 * s, y: 14.0 * s))
        path.addLine(to: CGPoint(x: 18.5 * s, y: 20.0 * s))
        path.addLine(to: CGPoint(x: 14.5 * s, y: 23.5 * s))
        path.addLine(to: CGPoint(x: 7.0 * s, y: 23.5 * s))
        path.addLine(to: CGPoint(x: 3.5 * s, y: 19.5 * s))
        path.addLine(to: CGPoint(x: 3.5 * s, y: 13.5 * s))
        path.addLine(to: CGPoint(x: 7.0 * s, y: 9.0 * s))
        path.closeSubpath()
        
        return path
    }
    
    /// Generates closed/grabbing fist hand cursor during drag
    public static func createClosedHandPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 24.0
        
        path.addRoundedRect(in: CGRect(x: 3.0 * s, y: 5.0 * s, width: 14.0 * s, height: 14.0 * s), cornerWidth: 4.0 * s, cornerHeight: 4.0 * s)
        path.move(to: CGPoint(x: 1.5 * s, y: 10.0 * s))
        path.addLine(to: CGPoint(x: 4.0 * s, y: 14.0 * s))
        
        return path
    }
    
    // MARK: - CoreGraphics Drawing Function
    
    /// Draws the crisp vector cursor with tactile click squash onto any CGContext (for live canvas and offline video render)
    public static func drawCursor(
        in context: CGContext,
        at position: CGPoint,
        type: CursorType,
        size: CGFloat = 26.0,
        clickProgress: Double? = nil, // 0.0...1.0 for active click animation
        isRightClick: Bool = false
    ) {
        context.saveGState()
        
        // Ensure highest rasterization quality and smooth anti-aliasing
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        
        // 1. Tactile click press animation: squash slightly on click (NO ripple rings)
        var scaleFactor: CGFloat = 1.0
        var pressOffsetY: CGFloat = 0.0
        if let progress = clickProgress, progress >= 0.0 && progress <= 0.35 {
            let normalized = progress / 0.35
            let squash = CGFloat(sin(normalized * .pi))
            scaleFactor = 1.0 - (0.16 * squash)
            pressOffsetY = 1.5 * squash
        }
        
        // 2. Position and scale cursor
        let effectiveSize = size * scaleFactor
        let hotspot = hotspot(for: type, size: effectiveSize)
        let drawOrigin = CGPoint(x: position.x - hotspot.x, y: position.y - hotspot.y + pressOffsetY)
        
        context.translateBy(x: drawOrigin.x, y: drawOrigin.y)
        
        let path: CGPath
        switch type {
        case .arrow:
            path = createModernArrowPath(size: effectiveSize)
        case .iBeam:
            path = createIBeamPath(size: effectiveSize)
        case .pointingHand:
            path = createPointingHandPath(size: effectiveSize)
        case .closedHand:
            path = createClosedHandPath(size: effectiveSize)
        case .openHand:
            path = createPointingHandPath(size: effectiveSize)
        }
        
        // 3. Subtle soft drop shadow for separation on any background
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1.8),
            blur: 4.0,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.38)
        )
        
        // 4. Crisp Black outer border (guarantees clear contrast on bright/white backgrounds)
        context.addPath(path)
        context.setStrokeColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))
        let strokeWidth = max(1.5, effectiveSize * 0.075)
        context.setLineWidth(strokeWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
        
        // 5. Pure White body fill (guarantees clear contrast on dark backgrounds)
        context.addPath(path)
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fillPath()
        
        context.restoreGState()
    }
}
