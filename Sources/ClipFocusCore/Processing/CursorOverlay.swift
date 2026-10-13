import Foundation
import CoreGraphics
import AppKit

/// Per-frame evaluated state of the styled cursor overlay (Screen Studio / FocuSee style).
public struct CursorOverlayState: Sendable, Equatable {
    /// Normalized cursor tip position inside the recorded video (0...1, top-left origin)
    public var position: CGPoint
    /// Click/drag "press" animation scale (1.0 = rest, ~0.80 = pressed/dragging)
    public var scale: CGFloat
    /// Active cursor shape (arrow, ibeam, hand, resize, etc.)
    public var shape: CursorShape
    /// Whether the cursor should be drawn at all on this frame
    public var isVisible: Bool

    public init(
        position: CGPoint,
        scale: CGFloat,
        shape: CursorShape = .arrow,
        isVisible: Bool
    ) {
        self.position = position
        self.scale = scale
        self.shape = shape
        self.isVisible = isVisible
    }

    public static let hidden = CursorOverlayState(
        position: CGPoint(x: 0.5, y: 0.5),
        scale: 1.0,
        shape: .arrow,
        isVisible: false
    )
}

/// Visual properties and high-res raster/vector artwork for a specific cursor shape
public struct CursorShapeDescriptor: Sendable {
    public let shape: CursorShape
    public let image: CGImage
    public let canvasSize: CGSize   // Logical dimensions in cursor points
    public let hotspot: CGPoint     // Hotspot inside canvasSize (top-left origin)
    public let arrowHeight: CGFloat // Visual height for normalization

    public init(
        shape: CursorShape,
        image: CGImage,
        canvasSize: CGSize,
        hotspot: CGPoint,
        arrowHeight: CGFloat
    ) {
        self.shape = shape
        self.image = image
        self.canvasSize = canvasSize
        self.hotspot = hotspot
        self.arrowHeight = arrowHeight
    }
}

/// Pre-indexed cursor telemetry used to evaluate the styled cursor overlay at any source time.
/// Shared 1:1 between the live editor preview and the offline export compositor.
public struct CursorOverlayTrack: Sendable {
    private let positions: [(time: TimeInterval, point: CGPoint)]
    private let shapes: [(time: TimeInterval, shape: CursorShape)]
    private let buttonEvents: [(time: TimeInterval, isDown: Bool)]

    /// Cursor height expressed as a fraction of the video card width (before `sizeScale`).
    public static let baseHeightFraction: CGFloat = 0.020

    public init(events: [TelemetryEvent]) {
        let mouseEvents = events
            .filter {
                $0.type == .mouseMove || $0.type == .mouseDrag ||
                $0.type == .mouseClick || $0.type == .mouseUp
            }
            .sorted { $0.timestamp < $1.timestamp }

        self.positions = mouseEvents.compactMap { ev in
            guard let p = ev.position else { return nil }
            return (ev.timestamp, p)
        }

        var parsedShapes: [(time: TimeInterval, shape: CursorShape)] = []
        for ev in mouseEvents {
            if let raw = ev.cursorType, let s = CursorShape(rawValue: raw) {
                if parsedShapes.isEmpty || parsedShapes.last!.shape != s {
                    parsedShapes.append((ev.timestamp, s))
                }
            }
        }
        self.shapes = parsedShapes

        // Extract button press/release sequence for press-and-hold drag scaling
        var btnEvents: [(time: TimeInterval, isDown: Bool)] = []
        for ev in mouseEvents {
            if ev.type == .mouseClick {
                btnEvents.append((ev.timestamp, true))
            } else if ev.type == .mouseDrag {
                if btnEvents.isEmpty || btnEvents.last!.isDown == false {
                    btnEvents.append((ev.timestamp, true))
                }
            } else if ev.type == .mouseUp {
                if btnEvents.last?.isDown == true {
                    btnEvents.append((ev.timestamp, false))
                }
            }
        }
        self.buttonEvents = btnEvents
    }

    public var isEmpty: Bool { positions.isEmpty }

    /// Evaluate cursor state at a given source-video timestamp (nil = timeline gap → hidden).
    public func state(atSourceTime time: TimeInterval?) -> CursorOverlayState {
        guard let time = time, !positions.isEmpty else { return .hidden }
        return CursorOverlayState(
            position: position(at: time),
            scale: buttonScale(at: time),
            shape: shape(at: time),
            isVisible: true
        )
    }

    // MARK: - Position Interpolation

    private func position(at time: TimeInterval) -> CGPoint {
        if time <= positions[0].time { return positions[0].point }
        if time >= positions[positions.count - 1].time { return positions[positions.count - 1].point }

        var low = 0
        var high = positions.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if positions[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        let e0 = positions[low]
        let e1 = positions[min(positions.count - 1, low + 1)]
        let dt = e1.time - e0.time
        if dt <= 0.0001 { return e1.point }

        let motionDur = min(dt, 0.20)
        let motionStart = e1.time - motionDur
        if time <= motionStart { return e0.point }

        let p = max(0.0, min(1.0, (time - motionStart) / motionDur))
        let s = CGFloat(p * p * (3.0 - 2.0 * p))
        return CGPoint(
            x: e0.point.x + (e1.point.x - e0.point.x) * s,
            y: e0.point.y + (e1.point.y - e0.point.y) * s
        )
    }

    // MARK: - Shape Evaluation

    private func shape(at time: TimeInterval) -> CursorShape {
        guard !shapes.isEmpty else { return .arrow }
        if time <= shapes[0].time { return shapes[0].shape }
        if time >= shapes[shapes.count - 1].time { return shapes[shapes.count - 1].shape }

        var low = 0
        var high = shapes.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if shapes[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        return shapes[low].shape
    }

    // MARK: - Click & Drag Scale Animation

    private func buttonScale(at time: TimeInterval) -> CGFloat {
        guard !buttonEvents.isEmpty, time >= buttonEvents[0].time else { return 1.0 }

        // Find last button event at or before `time`
        var low = 0
        var high = buttonEvents.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if buttonEvents[mid].time <= time { low = mid } else { high = mid - 1 }
        }

        let ev = buttonEvents[low]
        if ev.isDown {
            // Button is currently down (or dragging)
            let elapsed = time - ev.time
            // If held down for an extended period, does a mouseUp follow?
            let nextUp = (low + 1 < buttonEvents.count && !buttonEvents[low + 1].isDown) ? buttonEvents[low + 1].time : nil
            let maxHold = nextUp != nil ? (nextUp! - ev.time) : 0.35

            if elapsed < 0.08 {
                // Press down phase: 1.0 -> 0.76
                let p = elapsed / 0.08
                let eased = 1.0 - (1.0 - p) * (1.0 - p)
                return CGFloat(1.0 - (1.0 - 0.76) * eased)
            } else if elapsed <= maxHold {
                // Held down / dragging phase: stay tactilely pressed at 0.82
                return 0.82
            } else {
                // If no mouseUp occurred after 0.35s, gracefully recover to 1.0
                let recoverElapsed = elapsed - maxHold
                return Self.springRelease(elapsed: recoverElapsed, fromScale: 0.82)
            }
        } else {
            // Button was released at ev.time: spring release bounce
            let elapsed = time - ev.time
            return Self.springRelease(elapsed: elapsed, fromScale: 0.82)
        }
    }

    private static func springRelease(elapsed: TimeInterval, fromScale: CGFloat) -> CGFloat {
        let releaseDur: TimeInterval = 0.28
        guard elapsed >= 0, elapsed <= releaseDur else { return 1.0 }
        let p = elapsed / releaseDur
        let spring = 1.0 - exp(-6.0 * p) * cos(p * .pi * 1.5)
        return CGFloat(fromScale + (1.0 - fromScale) * spring)
    }
}

// MARK: - Vector & High-Res Cursor Artwork

public enum CursorArtwork {
    /// Pre-computed descriptors for all standard cursor shapes
    public static let allDescriptors: [CursorShape: CursorShapeDescriptor] = {
        var dict: [CursorShape: CursorShapeDescriptor] = [:]
        for shape in CursorShape.allCases {
            dict[shape] = makeDescriptor(for: shape)
        }
        return dict
    }()

    public static func descriptor(for shape: CursorShape) -> CursorShapeDescriptor {
        return allDescriptors[shape] ?? allDescriptors[.arrow]!
    }

    /// Master image for default arrow (backward-compatibility convenience)
    public static var masterImage: CGImage? {
        return descriptor(for: .arrow).image
    }

    public static var canvasSize: CGSize {
        return descriptor(for: .arrow).canvasSize
    }

    public static var hotspot: CGPoint {
        return descriptor(for: .arrow).hotspot
    }

    public static var arrowHeight: CGFloat {
        return descriptor(for: .arrow).arrowHeight
    }

    // MARK: - Descriptor Factory

    private static func makeDescriptor(for shape: CursorShape) -> CursorShapeDescriptor {
        switch shape {
        case .arrow:
            let img = makeArrowImage(pixelHeight: 512)!
            return CursorShapeDescriptor(
                shape: .arrow,
                image: img,
                canvasSize: CGSize(width: 19.0, height: 26.0),
                hotspot: CGPoint(x: 3.0, y: 2.5),
                arrowHeight: 20.0
            )

        case .iBeam:
            let img = makeIBeamImage(pixelHeight: 512)!
            return CursorShapeDescriptor(
                shape: .iBeam,
                image: img,
                canvasSize: CGSize(width: 15.0, height: 26.0),
                hotspot: CGPoint(x: 7.5, y: 13.0),
                arrowHeight: 20.0
            )

        case .pointingHand:
            return extractSystemCursorDescriptor(
                cursor: .pointingHand,
                shape: .pointingHand,
                arrowHeight: 22.0
            )

        case .openHand:
            return extractSystemCursorDescriptor(
                cursor: .openHand,
                shape: .openHand,
                arrowHeight: 22.0
            )

        case .closedHand:
            return extractSystemCursorDescriptor(
                cursor: .closedHand,
                shape: .closedHand,
                arrowHeight: 20.0
            )

        case .resizeLeftRight:
            return extractSystemCursorDescriptor(
                cursor: .resizeLeftRight,
                shape: .resizeLeftRight,
                arrowHeight: 18.0
            )

        case .resizeUpDown:
            return extractSystemCursorDescriptor(
                cursor: .resizeUpDown,
                shape: .resizeUpDown,
                arrowHeight: 20.0
            )

        case .crosshair:
            return extractSystemCursorDescriptor(
                cursor: .crosshair,
                shape: .crosshair,
                arrowHeight: 18.0
            )

        case .dragCopy:
            return extractSystemCursorDescriptor(
                cursor: .dragCopy,
                shape: .dragCopy,
                arrowHeight: 24.0
            )

        case .notAllowed:
            return extractSystemCursorDescriptor(
                cursor: .operationNotAllowed,
                shape: .notAllowed,
                arrowHeight: 24.0
            )
        }
    }

    private static func extractSystemCursorDescriptor(
        cursor: NSCursor,
        shape: CursorShape,
        arrowHeight: CGFloat
    ) -> CursorShapeDescriptor {
        let logical = cursor.image.size
        let hot = cursor.hotSpot

        // Extract the highest resolution bitmap representation available (up to 113x113 @3x/@4x)
        if let bestRep = cursor.image.representations.max(by: { $0.pixelsHigh < $1.pixelsHigh }) as? NSBitmapImageRep,
           let cg = bestRep.cgImage {
            return CursorShapeDescriptor(
                shape: shape,
                image: cg,
                canvasSize: logical,
                hotspot: hot,
                arrowHeight: arrowHeight
            )
        }

        var rect = CGRect(origin: .zero, size: logical)
        if let cg = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return CursorShapeDescriptor(
                shape: shape,
                image: cg,
                canvasSize: logical,
                hotspot: hot,
                arrowHeight: arrowHeight
            )
        }

        // Fallback to default arrow
        return descriptor(for: .arrow)
    }

    // MARK: - Custom Vector Arrow Artwork

    public static func makeArrowImage(pixelHeight: Int) -> CGImage? {
        let canvas = CGSize(width: 19.0, height: 26.0)
        let s = CGFloat(pixelHeight) / canvas.height
        let w = Int(ceil(canvas.width * s))
        let h = pixelHeight
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        let tipHotspot = CGPoint(x: 3.0, y: 2.5)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: s, y: -s)
        ctx.translateBy(x: tipHotspot.x, y: tipHotspot.y)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.0, y: 0.0))
        path.addLine(to: CGPoint(x: 0.0, y: 16.6))
        path.addLine(to: CGPoint(x: 3.9, y: 12.9))
        path.addLine(to: CGPoint(x: 6.5, y: 19.1))
        path.addLine(to: CGPoint(x: 9.2, y: 18.0))
        path.addLine(to: CGPoint(x: 6.6, y: 11.9))
        path.addLine(to: CGPoint(x: 11.9, y: 11.9))
        path.closeSubpath()

        // White outline with soft drop shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -0.9 * s),
            blur: 2.2 * s,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
        )
        ctx.addPath(path)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.setLineWidth(2.6)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()

        // Black interior
        ctx.addPath(path)
        ctx.setFillColor(CGColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        ctx.fillPath()

        return ctx.makeImage()
    }

    // MARK: - Custom Vector I-Beam Artwork

    public static func makeIBeamImage(pixelHeight: Int) -> CGImage? {
        let canvas = CGSize(width: 15.0, height: 26.0)
        let s = CGFloat(pixelHeight) / canvas.height
        let w = Int(ceil(canvas.width * s))
        let h = pixelHeight
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: s, y: -s)

        let path = CGMutablePath()
        let cx: CGFloat = 7.5
        let topY: CGFloat = 3.5
        let botY: CGFloat = 22.5
        let serifW: CGFloat = 4.2
        let stemHalfW: CGFloat = 0.9

        path.move(to: CGPoint(x: cx - serifW, y: topY))
        path.addLine(to: CGPoint(x: cx + serifW, y: topY))
        path.addLine(to: CGPoint(x: cx + stemHalfW, y: topY + 2.0))
        path.addLine(to: CGPoint(x: cx + stemHalfW, y: botY - 2.0))
        path.addLine(to: CGPoint(x: cx + serifW, y: botY))
        path.addLine(to: CGPoint(x: cx - serifW, y: botY))
        path.addLine(to: CGPoint(x: cx - stemHalfW, y: botY - 2.0))
        path.addLine(to: CGPoint(x: cx - stemHalfW, y: topY + 2.0))
        path.closeSubpath()

        // White outline with soft drop shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -0.9 * s),
            blur: 2.0 * s,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
        )
        ctx.addPath(path)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.setLineWidth(2.2)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()

        // Black interior
        ctx.addPath(path)
        ctx.setFillColor(CGColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        ctx.fillPath()

        return ctx.makeImage()
    }
}
