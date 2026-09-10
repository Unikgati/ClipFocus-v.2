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
            return CGPoint(x: size * 0.35, y: size * 0.5)
        case .pointingHand:
            return CGPoint(x: size * 0.28, y: 1.0)
        case .openHand, .closedHand:
            return CGPoint(x: size * 0.45, y: size * 0.45)
        }
    }
    
    // MARK: - Vector Path Generation
    
    /// Generates iconic Screen Studio / modern dark cursor arrow with rounded contours
    public static func createModernArrowPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 24.0
        
        path.move(to: CGPoint(x: 1.0 * s, y: 1.0 * s))
        path.addLine(to: CGPoint(x: 1.0 * s, y: 19.5 * s))
        path.addLine(to: CGPoint(x: 5.5 * s, y: 15.5 * s))
        path.addLine(to: CGPoint(x: 9.5 * s, y: 23.5 * s))
        path.addLine(to: CGPoint(x: 13.0 * s, y: 21.8 * s))
        path.addLine(to: CGPoint(x: 9.0 * s, y: 14.0 * s))
        path.addLine(to: CGPoint(x: 15.0 * s, y: 14.0 * s))
        path.closeSubpath()
        
        return path
    }
    
    /// Generates sleek I-Beam text selection cursor
    public static func createIBeamPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 24.0
        let midX = 8.0 * s
        let topY = 2.0 * s
        let bottomY = 22.0 * s
        let serifW = 5.0 * s
        
        // Top crossbar
        path.move(to: CGPoint(x: midX - serifW, y: topY))
        path.addLine(to: CGPoint(x: midX + serifW, y: topY))
        // Center vertical stem
        path.move(to: CGPoint(x: midX, y: topY))
        path.addLine(to: CGPoint(x: midX, y: bottomY))
        // Bottom crossbar
        path.move(to: CGPoint(x: midX - serifW, y: bottomY))
        path.addLine(to: CGPoint(x: midX + serifW, y: bottomY))
        
        return path
    }
    
    /// Generates modern pointing hand cursor
    public static func createPointingHandPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 24.0
        
        path.move(to: CGPoint(x: 6.5 * s, y: 1.0 * s))
        path.addLine(to: CGPoint(x: 9.5 * s, y: 1.0 * s))
        path.addLine(to: CGPoint(x: 9.5 * s, y: 9.0 * s))
        path.addLine(to: CGPoint(x: 12.5 * s, y: 9.0 * s))
        path.addLine(to: CGPoint(x: 12.5 * s, y: 11.5 * s))
        path.addLine(to: CGPoint(x: 15.5 * s, y: 11.5 * s))
        path.addLine(to: CGPoint(x: 15.5 * s, y: 14.0 * s))
        path.addLine(to: CGPoint(x: 18.0 * s, y: 14.0 * s))
        path.addLine(to: CGPoint(x: 18.0 * s, y: 20.0 * s))
        path.addLine(to: CGPoint(x: 14.0 * s, y: 23.5 * s))
        path.addLine(to: CGPoint(x: 6.5 * s, y: 23.5 * s))
        path.addLine(to: CGPoint(x: 3.5 * s, y: 19.5 * s))
        path.addLine(to: CGPoint(x: 3.5 * s, y: 13.5 * s))
        path.addLine(to: CGPoint(x: 6.5 * s, y: 9.0 * s))
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
    
    /// Draws the styled vector cursor and animated click ripple onto any CGContext (for live canvas and offline video render)
    public static func drawCursor(
        in context: CGContext,
        at position: CGPoint,
        type: CursorType,
        size: CGFloat = 26.0,
        clickProgress: Double? = nil, // 0.0...1.0 for active click ripple
        isRightClick: Bool = false
    ) {
        context.saveGState()
        
        // 1. Draw animated expanding click ripple ring if clicking
        if let progress = clickProgress, progress >= 0.0 && progress <= 1.0 {
            context.saveGState()
            let ringColor = isRightClick ? CGColor(red: 1.0, green: 0.35, blue: 0.45, alpha: CGFloat(1.0 - progress) * 0.85)
                                        : CGColor(red: 0.15, green: 0.65, blue: 1.0, alpha: CGFloat(1.0 - progress) * 0.85)
            let radius = CGFloat(5.0 + progress * 24.0)
            let lineWidth = max(1.0, CGFloat(3.2 * (1.0 - progress)))
            
            context.setStrokeColor(ringColor)
            context.setLineWidth(lineWidth)
            context.addArc(center: position, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            context.strokePath()
            
            // Soft inner glow dot
            if progress < 0.5 {
                let innerAlpha = CGFloat((0.5 - progress) * 2.0 * 0.4)
                context.setFillColor(ringColor.copy(alpha: innerAlpha) ?? ringColor)
                context.addArc(center: position, radius: radius * 0.5, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                context.fillPath()
            }
            context.restoreGState()
        }
        
        // 2. Compute press scale animation (squash slightly on click)
        var scaleFactor: CGFloat = 1.0
        if let progress = clickProgress, progress >= 0.0 && progress <= 0.35 {
            let normalized = progress / 0.35
            scaleFactor = 1.0 - CGFloat(0.14 * sin(normalized * .pi))
        }
        
        // 3. Position and scale cursor
        let effectiveSize = size * scaleFactor
        let hotspot = hotspot(for: type, size: effectiveSize)
        let drawOrigin = CGPoint(x: position.x - hotspot.x, y: position.y - hotspot.y)
        
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
        
        // 4. Soft 3D drop shadow
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -2.5),
            blur: 5.0,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        )
        
        // 5. Crisp white outer stroke
        context.addPath(path)
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
        context.setLineWidth(max(1.8, effectiveSize * 0.08))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
        
        // 6. Deep dark body fill
        context.addPath(path)
        context.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0))
        context.fillPath()
        
        // 7. Subtle interior accent line for arrow
        if type == .arrow {
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(CGColor(red: 0.25, green: 0.27, blue: 0.35, alpha: 0.7))
            context.setLineWidth(1.0)
            context.strokePath()
            context.restoreGState()
        }
        
        context.restoreGState()
    }
}
