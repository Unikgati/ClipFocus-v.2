import Foundation
import CoreGraphics
import CoreImage
#if canImport(AppKit)
import AppKit
#endif

/// High-Definition Authentic Vector Cursor Engine
/// Renders standard authentic vector cursors (Arrow, I-Beam, Pointing Hand, Grab Hand)
/// directly via Quartz 2D (CGPath / CGContext) at 100% device Retina resolution.
/// Eliminates upside-down flipped coordinate issues and eliminates low-res bitmap blur.
public final class CustomCursorRenderer: @unchecked Sendable {
    public static let shared = CustomCursorRenderer()
    
    public init() {}
    
    // MARK: - Hotspot Offsets (Relative to cursor canvas origin)
    
    public static func hotspot(for type: CursorType, size: CGFloat) -> CGPoint {
        switch type {
        case .arrow:
            // Tip of arrow in 256x256 SVG canvas is at (84.1, 48.56)
            return CGPoint(x: size * (84.1 / 256.0), y: size * (48.56 / 256.0))
        case .iBeam:
            // Center of vertical I-beam is at (128.5 / 257.0, 128.0 / 256.0)
            return CGPoint(x: size * 0.50, y: size * 0.50)
        case .pointingHand:
            // Tip of pointing index finger is at (89.5 / 257.0, 41.5 / 257.0)
            return CGPoint(x: size * (89.5 / 257.0), y: size * (41.5 / 257.0))
        case .openHand, .closedHand:
            // Center of palm
            return CGPoint(x: size * 0.50, y: size * 0.50)
        }
    }
    
    // MARK: - Pre-compiled Vector Paths
    
    private static let rawArrowPath: CGPath = {
        parseSVGPath("M84.1 48.56V173.06L110.8 146.56L136.3 207.56L158.3 197.06L133.8 139.06H172.8L84.1 48.56Z")
    }()
    
    private static let rawPointingHandPath: CGPath = {
        parseSVGPath("M81.0183 180.026C77.6138 175.993 73.4782 167.747 66.1179 157.738C61.9463 152.076 51.6011 141.415 48.5203 136C45.8471 131.214 46.1348 129.069 46.7702 125.103C47.897 118.048 55.6169 112.555 63.8523 113.296C70.0737 113.847 75.3482 117.7 80.0953 121.34C86.5499 126.275 89.6466 134.286 93.087 141.647C93.8232 143.222 94.2708 143.773 94 142C93.1537 136.459 83.6081 86.5647 83.5009 86.0046L83.495 85.9739L78.7682 61.3943C77.1058 52.7503 80.7622 42.5647 89.5 41.4999C98.1629 40.4443 106.163 46.1267 108.449 54.549L113.464 73.0246C113.821 74.3406 114.109 75.6552 114.333 77.0004C115.57 84.443 119.843 110.194 119.996 111.929C119.97 110.998 119.827 103.622 119.701 97.0462C119.575 90.4682 123.421 85.5 130 85.5C146 85.5 152.62 94.02 152.62 98.5C152.62 92 161.371 87.4611 167 87.4611C175.32 87.4611 181.08 89.468 183 94.5C184.92 99.5319 185.899 113.5 186 114C186.298 115.47 186.93 106.506 191 103C197.838 97.1093 208.5 100.5 209.881 111C210.271 113.967 210.36 119.705 210.36 124.647C210.36 130.455 210.216 133.949 209.881 138.151C209.509 142.644 208.478 152.8 206.98 157.72C205.966 161.045 202.645 168.456 199.331 173.039C199.22 173.193 199.113 173.336 199 173.489C197.587 175.404 187.496 189.232 186.192 195.112C184.778 201.426 185.245 201.471 184.969 205.953C184.778 209.048 185.547 212.822 186.038 214.851C186.224 215.62 185.709 216.394 184.922 216.472C182.015 216.763 175.549 217.291 171.627 216.704C166.94 215.996 166.893 208.615 165.395 205.942C163.333 202.257 157.368 201.089 155.654 203.807C152.957 208.11 147.155 215.827 143.055 216.311C135.36 217.217 119.716 216.703 106.964 216.552C106.164 216.542 105.558 215.811 105.658 215.017C106.063 211.79 106.53 204.298 102.705 201.28C99.0493 198.37 94.7559 193.472 90.9918 190.372L81.0183 180.026Z")
    }()
    
    private static let rawPointingHandLines: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 175, y: 183)); path.addLine(to: CGPoint(x: 175, y: 145))
        path.move(to: CGPoint(x: 152, y: 182.899)); path.addLine(to: CGPoint(x: 152, y: 144.92))
        path.move(to: CGPoint(x: 128.7, y: 143.92)); path.addLine(to: CGPoint(x: 128.7, y: 181.899))
        return path
    }()
    
    private static let rawGrabHandPath: CGPath = {
        parseSVGPath("M86.7382 132.622C85.5698 128.133 84.4015 122.482 81.898 114.041C79.9071 107.372 77.8208 103.757 76.2948 99.279C74.447 93.8316 72.6826 90.6469 70.3817 85.1396C68.7246 81.2007 66.0422 72.5925 64.9335 67.8993C63.5148 61.8054 65.3269 56.8368 67.8424 53.4606C70.8586 49.4019 79.311 47.5941 84.02 49.2583C88.4429 50.8147 92.8897 55.3882 94.9402 58.6925C98.3736 64.1999 99.1962 66.2591 103.488 77.154C108.173 89.0307 110.212 100.117 110.772 103.864L111.781 110.109C111.796 110.198 111.784 110.202 111.782 110.111C111.364 97.7916 110.546 73.5383 110.808 60.1771C110.832 58.6686 111.571 53.1493 111.809 51.6168C112.739 45.6306 115.445 42.0389 119.833 39.8958C124.744 37.4894 130.872 37.3218 136.535 39.6923C141.578 41.7635 143.998 46.2771 144.725 51.9281C144.892 53.2331 145.846 63.7449 145.834 65.1816C145.679 77.4533 145.905 84.8283 146.012 91.2096C146.06 93.9753 146.048 110.665 146.215 108.797C146.942 100.943 147.336 70.6171 150.316 61.6018C152.033 56.4178 155.144 52.6704 159.782 50.4795C164.92 48.0491 173.051 49.6414 176.52 53.3888C179.918 57.0403 181.837 61.6737 182.266 67.193C182.648 72.0418 182.04 77.9322 182.028 82.0986C182.028 92.4787 181.777 97.9501 181.587 107.492C181.575 107.947 181.408 111.06 181.861 109.671C182.981 106.319 184.102 103.182 185.032 100.752C185.616 99.2551 187.905 93.4006 189.312 90.4673C190.671 87.6658 191.827 86.0495 194.259 82.2303C196.644 78.483 199.207 76.8667 202.223 75.5138C208.661 72.7003 215.444 76.8547 217.733 82.5895C218.758 85.1636 217.84 91.1258 217.399 95.819C216.672 103.565 214.371 111.455 213.203 115.55C211.677 120.901 209.936 130.336 209.149 134.717C208.291 139.435 206.36 151.263 204.869 156.507C203.844 160.111 200.447 168.216 197.097 173.077C197.097 173.077 184.293 188.043 182.886 194.771C181.491 201.512 181.956 201.559 181.682 206.324C181.48 209.699 182.283 213.819 182.772 215.949C182.946 216.707 182.439 217.461 181.666 217.544C178.79 217.853 172.328 218.419 168.413 217.782C163.752 217.04 157.982 207.713 156.492 204.876C154.441 200.949 150.066 201.703 148.361 204.6C145.679 209.186 139.909 217.411 135.831 217.926C128.176 218.892 112.611 218.333 99.9277 218.181C99.1337 218.172 98.5306 217.45 98.6255 216.662C99.0313 213.29 99.5498 205.16 95.7032 201.907C92.0671 198.794 85.8083 192.52 82.0649 189.216L72.1461 178.189C68.7604 173.879 64.6474 165.103 57.3275 154.424C53.1788 148.39 45.084 141.434 42.0202 135.52C39.3617 130.431 38.0741 124.098 39.7551 119.656C42.4374 112.544 47.8022 108.917 55.9923 109.695C62.1796 110.294 66.1018 112.161 70.7513 116.124C73.4336 118.399 77.5823 122.518 79.6925 125.08C81.6357 127.414 82.1126 128.384 84.1869 131.174C86.9289 134.849 87.7873 136.669 86.7382 132.622Z")
    }()
    
    private static let rawGrabHandLines: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 169.6, y: 181.36)); path.addLine(to: CGPoint(x: 169.6, y: 139.76))
        path.move(to: CGPoint(x: 146.6, y: 181.36)); path.addLine(to: CGPoint(x: 146.6, y: 140.4))
        path.move(to: CGPoint(x: 122.92, y: 140.4)); path.addLine(to: CGPoint(x: 122.92, y: 180.08))
        return path
    }()
    
    // MARK: - CoreGraphics Direct Vector Drawing Function
    
    /// Draws the crisp authentic vector cursor with tactile click squash onto any CGContext
    public static func drawCursor(
        in context: CGContext,
        at position: CGPoint,
        type: CursorType,
        size: CGFloat = 28.0,
        clickProgress: Double? = nil,
        isRightClick: Bool = false
    ) {
        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        
        // Normalize coordinate system:
        // In macOS CALayer (with isFlipped NSView), context.ctm.d < 0 (screen coordinates: Y goes down from top).
        // In unflipped Quartz CGBitmapContext (ctm.d > 0), flip Y around position so that screen coordinates (Y down) apply universally.
        if context.ctm.d > 0 {
            context.translateBy(x: position.x, y: position.y)
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: -position.x, y: -position.y)
        }
        
        // 1. Tactile click press animation: squash slightly on click (NO ripple rings)
        var scaleFactor: CGFloat = 1.0
        var pressOffsetY: CGFloat = 0.0
        if let progress = clickProgress, progress >= 0.0 && progress <= 0.35 {
            let normalized = progress / 0.35
            let squash = CGFloat(sin(normalized * .pi))
            scaleFactor = 1.0 - (0.16 * squash)
            pressOffsetY = 1.5 * squash
        }
        
        let effectiveSize = size * scaleFactor
        let hotspot = hotspot(for: type, size: effectiveSize)
        
        // Draw the vector shape directly into the context
        switch type {
        case .arrow:
            drawArrowVector(in: context, at: position, hotspot: hotspot, size: effectiveSize, offsetY: pressOffsetY)
        case .iBeam:
            drawIBeamVector(in: context, at: position, size: effectiveSize, offsetY: pressOffsetY)
        case .pointingHand:
            drawPointingHandVector(in: context, at: position, hotspot: hotspot, size: effectiveSize, offsetY: pressOffsetY)
        case .openHand, .closedHand:
            drawGrabHandVector(in: context, at: position, hotspot: hotspot, size: effectiveSize, offsetY: pressOffsetY)
        }
        
        context.restoreGState()
    }
    
    // MARK: - Dedicated Vector Drawing Routines
    
    private static func drawArrowVector(
        in context: CGContext,
        at position: CGPoint,
        hotspot: CGPoint,
        size: CGFloat,
        offsetY: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: position.x - hotspot.x, y: position.y - hotspot.y + offsetY)
        let s = size / 256.0
        context.scaleBy(x: s, y: s)
        
        // Soft drop shadow
        context.setShadow(offset: CGSize(width: 1.5 / s, height: 3.5 / s), blur: 4.0 / s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.38))
        
        // Fill pure white
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(rawArrowPath)
        context.fillPath()
        
        // Crisp solid black outline
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(7.5)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(rawArrowPath)
        context.strokePath()
        
        context.restoreGState()
    }
    
    private static func drawIBeamVector(
        in context: CGContext,
        at position: CGPoint,
        size: CGFloat,
        offsetY: CGFloat
    ) {
        let path = createIBeamPath(size: size)
        
        context.saveGState()
        context.translateBy(x: position.x, y: position.y + offsetY)
        
        // Soft drop shadow
        context.setShadow(offset: CGSize(width: 1.0, height: 2.5), blur: 3.5, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.40))
        
        // Fill pure white
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(path)
        context.fillPath()
        
        // Stroke black
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(1.6)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        
        context.restoreGState()
    }
    
    private static func drawPointingHandVector(
        in context: CGContext,
        at position: CGPoint,
        hotspot: CGPoint,
        size: CGFloat,
        offsetY: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: position.x - hotspot.x, y: position.y - hotspot.y + offsetY)
        let s = size / 257.0
        context.scaleBy(x: s, y: s)
        
        // Drop shadow
        context.setShadow(offset: CGSize(width: 1.5 / s, height: 3.5 / s), blur: 4.0 / s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        
        // Fill white
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(rawPointingHandPath)
        context.fillPath()
        
        // Stroke black
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(7.0)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(rawPointingHandPath)
        context.strokePath()
        
        // Crease lines
        context.setLineWidth(6.0)
        context.addPath(rawPointingHandLines)
        context.strokePath()
        
        context.restoreGState()
    }
    
    private static func drawGrabHandVector(
        in context: CGContext,
        at position: CGPoint,
        hotspot: CGPoint,
        size: CGFloat,
        offsetY: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: position.x - hotspot.x, y: position.y - hotspot.y + offsetY)
        let s = size / 257.0
        context.scaleBy(x: s, y: s)
        
        // Drop shadow
        context.setShadow(offset: CGSize(width: 1.5 / s, height: 3.5 / s), blur: 4.0 / s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        
        // Fill white
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(rawGrabHandPath)
        context.fillPath()
        
        // Stroke black
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(7.0)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(rawGrabHandPath)
        context.strokePath()
        
        // Crease lines
        context.setLineWidth(6.0)
        context.addPath(rawGrabHandLines)
        context.strokePath()
        
        context.restoreGState()
    }
    
    // MARK: - Compatibility Vector Paths
    
    public static func createModernArrowPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let s = size / 159.0
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 124.5 * s))
        path.addLine(to: CGPoint(x: 26.7 * s, y: 98.0 * s))
        path.addLine(to: CGPoint(x: 52.2 * s, y: 159.0 * s))
        path.addLine(to: CGPoint(x: 74.2 * s, y: 148.5 * s))
        path.addLine(to: CGPoint(x: 49.7 * s, y: 90.5 * s))
        path.addLine(to: CGPoint(x: 88.7 * s, y: 90.5 * s))
        path.closeSubpath()
        return path
    }
    
    public static func createIBeamPath(size: CGFloat = 24.0) -> CGPath {
        let path = CGMutablePath()
        let h = size
        let w = size * 0.45
        let barW = max(2.0, size * 0.10)
        let serifH = max(2.5, size * 0.12)
        
        // Top serif
        path.move(to: CGPoint(x: -w/2, y: -h/2))
        path.addLine(to: CGPoint(x: w/2, y: -h/2))
        path.addLine(to: CGPoint(x: w/2, y: -h/2 + serifH))
        path.addLine(to: CGPoint(x: barW/2, y: -h/2 + serifH))
        
        // Center stem
        path.addLine(to: CGPoint(x: barW/2, y: h/2 - serifH))
        
        // Bottom serif
        path.addLine(to: CGPoint(x: w/2, y: h/2 - serifH))
        path.addLine(to: CGPoint(x: w/2, y: h/2))
        path.addLine(to: CGPoint(x: -w/2, y: h/2))
        path.addLine(to: CGPoint(x: -w/2, y: h/2 - serifH))
        path.addLine(to: CGPoint(x: -barW/2, y: h/2 - serifH))
        
        // Left stem
        path.addLine(to: CGPoint(x: -barW/2, y: -h/2 + serifH))
        path.addLine(to: CGPoint(x: -w/2, y: -h/2 + serifH))
        path.closeSubpath()
        return path
    }
    
    public static func createPointingHandPath(size: CGFloat = 24.0) -> CGPath {
        let transform = CGAffineTransform(scaleX: size / 257.0, y: size / 257.0)
        return rawPointingHandPath.copy(using: [transform]) ?? rawPointingHandPath
    }
    
    public static func createClosedHandPath(size: CGFloat = 24.0) -> CGPath {
        let transform = CGAffineTransform(scaleX: size / 257.0, y: size / 257.0)
        return rawGrabHandPath.copy(using: [transform]) ?? rawGrabHandPath
    }
    
    // MARK: - Internal SVG Path Parser Helper
    
    private static func parseSVGPath(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        
        var currentPoint = CGPoint.zero
        var command: Character = "M"
        
        while !scanner.isAtEnd {
            let loc = scanner.currentIndex
            if let char = scanner.scanCharacter() {
                if char.isLetter {
                    command = char
                } else {
                    scanner.currentIndex = loc
                }
            }
            
            switch command {
            case "M":
                if let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    currentPoint = CGPoint(x: x, y: y)
                    path.move(to: currentPoint)
                }
            case "m":
                if let dx = scanner.scanDouble(), let dy = scanner.scanDouble() {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.move(to: currentPoint)
                }
            case "L":
                if let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    currentPoint = CGPoint(x: x, y: y)
                    path.addLine(to: currentPoint)
                }
            case "l":
                if let dx = scanner.scanDouble(), let dy = scanner.scanDouble() {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.addLine(to: currentPoint)
                }
            case "H":
                if let x = scanner.scanDouble() {
                    currentPoint = CGPoint(x: x, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                }
            case "h":
                if let dx = scanner.scanDouble() {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                }
            case "V":
                if let y = scanner.scanDouble() {
                    currentPoint = CGPoint(x: currentPoint.x, y: y)
                    path.addLine(to: currentPoint)
                }
            case "v":
                if let dy = scanner.scanDouble() {
                    currentPoint = CGPoint(x: currentPoint.x, y: currentPoint.y + dy)
                    path.addLine(to: currentPoint)
                }
            case "C":
                if let x1 = scanner.scanDouble(), let y1 = scanner.scanDouble(),
                   let x2 = scanner.scanDouble(), let y2 = scanner.scanDouble(),
                   let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    currentPoint = CGPoint(x: x, y: y)
                    path.addCurve(to: currentPoint, control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                }
            case "c":
                if let dx1 = scanner.scanDouble(), let dy1 = scanner.scanDouble(),
                   let dx2 = scanner.scanDouble(), let dy2 = scanner.scanDouble(),
                   let dx = scanner.scanDouble(), let dy = scanner.scanDouble() {
                    let cp1 = CGPoint(x: currentPoint.x + dx1, y: currentPoint.y + dy1)
                    let cp2 = CGPoint(x: currentPoint.x + dx2, y: currentPoint.y + dy2)
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.addCurve(to: currentPoint, control1: cp1, control2: cp2)
                }
            case "Z", "z":
                path.closeSubpath()
            default:
                _ = scanner.scanDouble()
            }
        }
        return path
    }
}
