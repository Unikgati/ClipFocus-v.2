import Foundation
import AVFoundation
import CoreImage
import CoreGraphics

/// Configuration parameters for offline video compositing and export rendering.
public struct VideoCompositorConfig: Sendable {
    public var renderSize: CGSize
    public var padding: CGFloat
    public var cornerRadius: CGFloat
    public var shadowRadius: CGFloat
    
    // Background Styling
    public var activeBackgroundIndex: Int
    public var activeColorIndex: Int?
    
    // Zoom Keyframes & Telemetry
    public var zoomKeyframes: [ZoomKeyframe]
    public var telemetryEvents: [TelemetryEvent]
    public var tiltIntensity: Double
    public var disableZoom: Bool
    public var scaleFactor: CGFloat
    
    // Custom Vector Cursor Overlay
    public var isCursorOverlayEnabled: Bool
    public var cursorScale: CGFloat
    public var isClickRippleEnabled: Bool
    public var autoHideIdleCursor: Bool
    
    public init(
        renderSize: CGSize,
        padding: CGFloat = 20.0,
        cornerRadius: CGFloat = 16.0,
        shadowRadius: CGFloat = 24.0,
        activeBackgroundIndex: Int = 0,
        activeColorIndex: Int? = nil,
        zoomKeyframes: [ZoomKeyframe] = [],
        telemetryEvents: [TelemetryEvent] = [],
        tiltIntensity: Double = 1.0,
        disableZoom: Bool = false,
        scaleFactor: CGFloat = 1.0,
        isCursorOverlayEnabled: Bool = true,
        cursorScale: CGFloat = 1.35,
        isClickRippleEnabled: Bool = true,
        autoHideIdleCursor: Bool = true
    ) {
        self.renderSize = renderSize
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.activeBackgroundIndex = activeBackgroundIndex
        self.activeColorIndex = activeColorIndex
        self.zoomKeyframes = zoomKeyframes
        self.telemetryEvents = telemetryEvents
        self.tiltIntensity = tiltIntensity
        self.disableZoom = disableZoom
        self.scaleFactor = scaleFactor > 0 ? scaleFactor : 1.0
        self.isCursorOverlayEnabled = isCursorOverlayEnabled
        self.cursorScale = cursorScale
        self.isClickRippleEnabled = isClickRippleEnabled
        self.autoHideIdleCursor = autoHideIdleCursor
    }
}

/// Offline Video Compositor Engine
/// Leverages AVFoundation and Core Image Metal shaders to burn zoom animations, 3D tilt,
/// customizable canvas backgrounds, and video card styling directly into exported video files.
public final class VideoCompositorEngine: Sendable {
    public static let shared = VideoCompositorEngine()
    private let autoZoomEngine = AutoZoomEngine()
    
    // Exact CIColor definitions matching the EditorStudioView presets
    private static let gradientPresets: [(CIColor, CIColor)] = [
        // 0: Orange -> Blue
        (CIColor(red: 1.0, green: 0.50, blue: 0.0), CIColor(red: 0.0, green: 0.40, blue: 1.0)),
        // 1: Red -> Purple
        (CIColor(red: 1.0, green: 0.20, blue: 0.35), CIColor(red: 0.65, green: 0.30, blue: 0.90)),
        // 2: Blue -> Pink
        (CIColor(red: 0.0, green: 0.45, blue: 1.0), CIColor(red: 1.0, green: 0.25, blue: 0.55)),
        // 3: Indigo -> Dark
        (CIColor(red: 0.35, green: 0.30, blue: 0.85), CIColor(red: 0.05, green: 0.05, blue: 0.08)),
        // 4: Green -> Teal
        (CIColor(red: 0.20, green: 0.80, blue: 0.40), CIColor(red: 0.15, green: 0.70, blue: 0.80)),
        // 5: Pink -> Cyan
        (CIColor(red: 1.0, green: 0.25, blue: 0.60), CIColor(red: 0.20, green: 0.70, blue: 0.95))
    ]
    
    private static let paletteColors: [CIColor] = [
        CIColor(red: 0.0, green: 0.48, blue: 1.0),       // Blue
        CIColor(red: 0.35, green: 0.34, blue: 0.84),    // Indigo
        CIColor(red: 0.19, green: 0.69, blue: 0.78),    // Teal
        CIColor(red: 0.20, green: 0.68, blue: 0.90),    // Cyan
        CIColor(red: 1.0, green: 0.80, blue: 0.0),       // Yellow
        CIColor(red: 1.0, green: 0.58, blue: 0.0),       // Orange
        CIColor(red: 1.0, green: 0.18, blue: 0.33),      // Pink
        CIColor(red: 0.15, green: 0.15, blue: 0.15),     // Gray 15%
        CIColor(red: 0.25, green: 0.25, blue: 0.25),     // Gray 25%
        CIColor(red: 0.35, green: 0.35, blue: 0.35),     // Gray 35%
        CIColor(red: 0.50, green: 0.50, blue: 0.50),     // Gray 50%
        CIColor(red: 0.65, green: 0.65, blue: 0.65),     // Gray 65%
        CIColor(red: 0.80, green: 0.80, blue: 0.80),     // Gray 80%
        CIColor(red: 0.95, green: 0.95, blue: 0.95),     // Gray 95%
        CIColor(red: 0.0, green: 0.25, blue: 0.55),      // Tinted blue
        CIColor(red: 0.25, green: 0.18, blue: 0.50),     // Tinted purple
        CIColor(red: 0.15, green: 0.45, blue: 0.20),     // Tinted green
        CIColor(red: 0.10, green: 0.40, blue: 0.45),     // Tinted teal
        CIColor(red: 0.60, green: 0.50, blue: 0.10),     // Tinted yellow
        CIColor(red: 0.60, green: 0.35, blue: 0.10),     // Tinted orange
        CIColor(red: 0.60, green: 0.12, blue: 0.18)      // Tinted red
    ]
    
    public init() {}
    
    /// Constructs an AVVideoComposition that runs per-frame Core Image compositing on Apple Silicon Metal shaders.
    public func buildVideoComposition(
        for asset: AVAsset,
        config: VideoCompositorConfig
    ) -> AVVideoComposition {
        let renderSize = config.renderSize
        let autoZoom = self.autoZoomEngine
        
        let videoComp = AVMutableVideoComposition(asset: asset) { request in
            let sourceImage = request.sourceImage
            let srcExtent = sourceImage.extent
            let srcW = max(1.0, srcExtent.width)
            let srcH = max(1.0, srcExtent.height)
            
            let timeSec = request.compositionTime.seconds
            
            // 1. Evaluate Viewport for current frame
            let viewport: ViewportState
            if config.disableZoom {
                viewport = .fullScreen
            } else {
                viewport = autoZoom.evaluateViewport(at: timeSec, with: config.zoomKeyframes, telemetry: config.telemetryEvents)
            }
            
            let zoomScale = max(1.0, viewport.scale)
            let fx = max(0.0, min(1.0, viewport.focusPoint.x))
            let fy = max(0.0, min(1.0, viewport.focusPoint.y))
            let fy_ci = 1.0 - fy // Flip for Core Image (where y=0 is at bottom)
            
            // 2. Generate Canvas Background with Synchronized Camera Parallax
            let bgScale = max(1.0, 1.0 + (zoomScale - 1.0) * 0.40)
            let bgOffsetX = (0.5 - fx) * renderSize.width * (bgScale - 1.0) * 0.40
            let bgOffsetY = (0.5 - fy_ci) * renderSize.height * (bgScale - 1.0) * 0.40
            
            var bgTrans = CGAffineTransform(translationX: renderSize.width * 0.5 + bgOffsetX, y: renderSize.height * 0.5 + bgOffsetY)
            bgTrans = bgTrans.scaledBy(x: bgScale, y: bgScale)
            bgTrans = bgTrans.translatedBy(x: -renderSize.width * 0.5, y: -renderSize.height * 0.5)
            
            let bgImage: CIImage
            if let colorIdx = config.activeColorIndex, colorIdx < Self.paletteColors.count {
                let baseColor = Self.paletteColors[colorIdx]
                let solidBase = CIImage(color: baseColor)
                
                // Add subtle radial vignette / highlight so camera parallax is beautifully visible on solid backgrounds too
                let radialGrad = CIFilter(name: "CIRadialGradient")!
                radialGrad.setValue(CIVector(x: renderSize.width * 0.5, y: renderSize.height * 0.5), forKey: "inputCenter")
                radialGrad.setValue(renderSize.width * 0.25, forKey: "inputRadius0")
                radialGrad.setValue(renderSize.width * 0.95, forKey: "inputRadius1")
                radialGrad.setValue(CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12), forKey: "inputColor0")
                radialGrad.setValue(CIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.18), forKey: "inputColor1")
                
                let rawVignette = radialGrad.outputImage ?? CIImage.empty()
                let movedVignette = rawVignette.transformed(by: bgTrans)
                let blendedBg = movedVignette.composited(over: solidBase)
                bgImage = blendedBg.cropped(to: CGRect(origin: .zero, size: renderSize))
            } else {
                let presetIdx = max(0, min(Self.gradientPresets.count - 1, config.activeBackgroundIndex))
                let (c0, c1) = Self.gradientPresets[presetIdx]
                
                let grad = CIFilter(name: "CILinearGradient")!
                grad.setValue(CIVector(x: 0, y: renderSize.height), forKey: "inputPoint0")
                grad.setValue(CIVector(x: renderSize.width, y: 0), forKey: "inputPoint1")
                grad.setValue(c0, forKey: "inputColor0")
                grad.setValue(c1, forKey: "inputColor1")
                
                let rawBg = grad.outputImage ?? CIImage(color: CIColor.black)
                bgImage = rawBg.transformed(by: bgTrans).cropped(to: CGRect(origin: .zero, size: renderSize))
            }
            
            // 3. Compute Video Card Rect (Aspect-Fit within Canvas minus Padding)
            let pad = config.padding
            let availW = max(100.0, renderSize.width - (pad * 2.0))
            let availH = max(100.0, renderSize.height - (pad * 2.0))
            let vRatio = srcW / srcH
            
            let fitByWidth = (availW / availH) <= vRatio
            let baseCardW = fitByWidth ? availW : (availH * vRatio)
            let baseCardH = fitByWidth ? (availW / vRatio) : availH
            let baseCardRect = CGRect(x: 0, y: 0, width: baseCardW, height: baseCardH)
            
            // Dynamic Zoom Scale and Viewport Translation:
            // Scale pan offsets proportionally based on export render resolution vs preview reference (850pt width)
            let panScale = baseCardW / 850.0
            let scaledPanX = (viewport.positionOffsetX * 2.0) * panScale
            let scaledPanY = (viewport.positionOffsetY * 2.0) * panScale
            
            let transX = (0.5 - fx) * baseCardW * zoomScale + scaledPanX
            // In preview (Cocoa flipped coordinates), Y=0 is at top, so down is positive:
            let transY_preview = (0.5 - fy) * baseCardH * zoomScale + scaledPanY
            
            // 4. Transform Source Video to Fill Base Card Rect
            let videoTrans = CGAffineTransform(scaleX: baseCardW / srcW, y: baseCardH / srcH)
            let transformedVideo = sourceImage.transformed(by: videoTrans)
            
            // 4b. Overlay Custom Vector Cursor (Screen Studio / FocuSee style)
            var videoWithCursor = transformedVideo
            if config.isCursorOverlayEnabled,
               let cursorInfo = Self.evaluateCursorState(
                    at: timeSec,
                    events: config.telemetryEvents,
                    autoHideIdle: config.autoHideIdleCursor,
                    clickRipple: config.isClickRippleEnabled
               ),
               let cursorCI = Self.renderCursorOverlayImage(
                    cursorInfo: cursorInfo,
                    cardSize: CGSize(width: baseCardW, height: baseCardH),
                    scale: config.cursorScale * (baseCardW / 850.0)
               ) {
                videoWithCursor = cursorCI.composited(over: transformedVideo)
            }
            
            // 5. Generate Card Mask with Rounded Corners
            let rectGen = CIFilter(name: "CIRoundedRectangleGenerator")!
            rectGen.setValue(CIVector(cgRect: baseCardRect), forKey: "inputExtent")
            rectGen.setValue(config.cornerRadius, forKey: "inputRadius")
            rectGen.setValue(CIColor.white, forKey: "inputColor")
            
            guard let cardMask = rectGen.outputImage else {
                request.finish(with: sourceImage, context: nil)
                return
            }
            
            // Clip video cleanly inside floating rounded card
            let blend = CIFilter(name: "CIBlendWithMask")!
            blend.setValue(videoWithCursor, forKey: kCIInputImageKey)
            blend.setValue(cardMask, forKey: kCIInputMaskImageKey)
            blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            
            guard let baseCard = blend.outputImage else {
                request.finish(with: sourceImage, context: nil)
                return
            }
            
            // 6. True 3D Perspective Projection (1:1 Exact Match with NativeVideoPlayerView CATransform3D)
            let pitch = viewport.pitch * config.tiltIntensity
            let yaw = viewport.yaw * config.tiltIntensity
            let roll = viewport.roll
            let tiltMagnitude = hypot(pitch / 16.0, yaw / 16.0)
            let tiltRatio = tanh(tiltMagnitude)
            
            let effectiveScaleFactor = config.scaleFactor > 0 ? config.scaleFactor : max(1.0, renderSize.width / 850.0)
            let elevationZ = (zoomScale - 1.0) * 45.0 * CGFloat(tiltRatio) * effectiveScaleFactor
            
            var cardTransform = CATransform3DIdentity
            cardTransform = CATransform3DTranslate(cardTransform, transX, transY_preview, elevationZ)
            cardTransform = CATransform3DScale(cardTransform, zoomScale, zoomScale, 1.0)
            
            let radPitch = CGFloat(pitch * .pi / 180.0)
            let radYaw = CGFloat(yaw * .pi / 180.0)
            let radRoll = CGFloat(roll * .pi / 180.0)
            cardTransform = CATransform3DRotate(cardTransform, radPitch, 1, 0, 0)
            cardTransform = CATransform3DRotate(cardTransform, radYaw, 0, 1, 0)
            cardTransform = CATransform3DRotate(cardTransform, radRoll, 0, 0, 1)
            
            var perspMatrix = CATransform3DIdentity
            let focalDistance = 850.0 * effectiveScaleFactor
            perspMatrix.m34 = -1.0 / focalDistance
            
            let combined = CATransform3DConcat(cardTransform, perspMatrix)
            let cx = renderSize.width * 0.5
            let cy = renderSize.height * 0.5
            
            // Project corner (x, y) from preview space (NSView flipped, Y down) into Core Image space (Y up)
            func projectCorner(x: CGFloat, y: CGFloat) -> CGPoint {
                let px = x * combined.m11 + y * combined.m21 + combined.m41
                let py = x * combined.m12 + y * combined.m22 + combined.m42
                let pw = x * combined.m14 + y * combined.m24 + combined.m44
                let w = pw != 0 ? pw : 1.0
                return CGPoint(x: cx + px / w, y: cy - py / w)
            }
            
            let pTL = projectCorner(x: -baseCardW * 0.5, y: -baseCardH * 0.5)
            let pTR = projectCorner(x: baseCardW * 0.5, y: -baseCardH * 0.5)
            let pBR = projectCorner(x: baseCardW * 0.5, y: baseCardH * 0.5)
            let pBL = projectCorner(x: -baseCardW * 0.5, y: baseCardH * 0.5)
            
            let minX = min(pTL.x, min(pTR.x, min(pBR.x, pBL.x)))
            let maxX = max(pTL.x, max(pTR.x, max(pBR.x, pBL.x)))
            let minY = min(pTL.y, min(pTR.y, min(pBR.y, pBL.y)))
            let maxY = max(pTL.y, max(pTR.y, max(pBR.y, pBL.y)))
            let cardBounds = CGRect(x: minX, y: minY, width: max(1.0, maxX - minX), height: max(1.0, maxY - minY))
            
            let persp = CIFilter(name: "CIPerspectiveTransform")!
            persp.setValue(baseCard, forKey: kCIInputImageKey)
            persp.setValue(CIVector(cgPoint: pTL), forKey: "inputTopLeft")
            persp.setValue(CIVector(cgPoint: pTR), forKey: "inputTopRight")
            persp.setValue(CIVector(cgPoint: pBR), forKey: "inputBottomRight")
            persp.setValue(CIVector(cgPoint: pBL), forKey: "inputBottomLeft")
            
            let finalCard = (persp.outputImage ?? baseCard).cropped(to: cardBounds.insetBy(dx: -4, dy: -4))
            
            // 7. Dynamic Drop Shadow matching 3D angle and zoom scale
            var compositeCard = finalCard
            if config.shadowRadius > 2.0 {
                let shadowGen = CIFilter(name: "CIRoundedRectangleGenerator")!
                shadowGen.setValue(CIVector(cgRect: baseCardRect), forKey: "inputExtent")
                shadowGen.setValue(config.cornerRadius, forKey: "inputRadius")
                let shadowAlpha = CGFloat(0.45 + (tiltRatio * 0.20))
                shadowGen.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: shadowAlpha), forKey: "inputColor")
                
                if let shadowImage = shadowGen.outputImage {
                    let perspShadow = CIFilter(name: "CIPerspectiveTransform")!
                    perspShadow.setValue(shadowImage, forKey: kCIInputImageKey)
                    perspShadow.setValue(CIVector(cgPoint: pTL), forKey: "inputTopLeft")
                    perspShadow.setValue(CIVector(cgPoint: pTR), forKey: "inputTopRight")
                    perspShadow.setValue(CIVector(cgPoint: pBR), forKey: "inputBottomRight")
                    perspShadow.setValue(CIVector(cgPoint: pBL), forKey: "inputBottomLeft")
                    
                    if let pShadow = perspShadow.outputImage {
                        // Crucial: Bounding pShadow before GaussianBlur prevents GPU pipeline infinite-plane stall and dropped frames
                        let boundedPShadow = pShadow.cropped(to: cardBounds.insetBy(dx: -2, dy: -2))
                        let blur = CIFilter(name: "CIGaussianBlur")!
                        blur.setValue(boundedPShadow, forKey: kCIInputImageKey)
                        let effectiveShadowRadius = (config.shadowRadius + (CGFloat(tiltRatio) * 12.0))
                        blur.setValue(effectiveShadowRadius, forKey: kCIInputRadiusKey)
                        
                        if let blurredShadow = blur.outputImage {
                            let shadowShiftX = CGFloat(-yaw * 1.5) * CGFloat(tiltRatio) * panScale
                            let shadowShiftY = (-12.0 - CGFloat(pitch * 1.2 * tiltRatio)) * panScale
                            let shadowShift = CGAffineTransform(translationX: shadowShiftX, y: shadowShiftY)
                            let shiftedShadow = blurredShadow.transformed(by: shadowShift)
                            // Crop shadow to bounded canvas extent to prevent GPU pipeline memory stall
                            let boundedShadow = shiftedShadow.cropped(to: CGRect(origin: .zero, size: renderSize).insetBy(dx: -80, dy: -80))
                            compositeCard = finalCard.composited(over: boundedShadow)
                        }
                    }
                }
            }
            
            // 8. Final Composite over Dynamic Canvas Background
            let finalFrame = compositeCard.composited(over: bgImage).cropped(to: CGRect(origin: .zero, size: renderSize))
            request.finish(with: finalFrame, context: nil)
        }
        
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 60)
        return videoComp
    }
    
    // MARK: - Cursor Evaluation & Rendering for Offline Video Export
    
    public static func evaluateCursorState(
        at time: Double,
        events: [TelemetryEvent],
        autoHideIdle: Bool,
        clickRipple: Bool
    ) -> (position: CGPoint, type: CursorType, clickProgress: Double?, isRightClick: Bool, opacity: Double)? {
        guard !events.isEmpty else { return nil }
        let mouseEvents = events.filter {
            $0.type == .mouseMove || $0.type == .mouseClick || $0.type == .mouseDrag
        }
        guard !mouseEvents.isEmpty else { return nil }
        
        var prevEvent: TelemetryEvent? = nil
        var nextEvent: TelemetryEvent? = nil
        
        for ev in mouseEvents {
            if ev.timestamp <= time {
                prevEvent = ev
            } else {
                nextEvent = ev
                break
            }
        }
        
        guard let prev = prevEvent ?? mouseEvents.first, let pos1 = prev.position else {
            return nil
        }
        
        var opacity: Double = 1.0
        let idleThreshold: TimeInterval = 2.0
        let timeSinceLastMove = time - prev.timestamp
        if autoHideIdle && timeSinceLastMove > idleThreshold {
            if let next = nextEvent {
                let timeUntilNext = next.timestamp - time
                if timeUntilNext < 0.3 {
                    opacity = max(0.0, min(1.0, 1.0 - (timeUntilNext / 0.3)))
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
        
        var finalPos = pos1
        if let next = nextEvent, let pos2 = next.position {
            let interval = next.timestamp - prev.timestamp
            if interval > 0.001 && interval < 0.15 {
                let factor = (time - prev.timestamp) / interval
                let clampedFactor = max(0.0, min(1.0, factor))
                finalPos = CGPoint(
                    x: pos1.x + (pos2.x - pos1.x) * clampedFactor,
                    y: pos1.y + (pos2.y - pos1.y) * clampedFactor
                )
            }
        }
        
        let type = prev.cursorType ?? .arrow
        
        var clickProgress: Double? = nil
        var isRight = false
        if let clickEv = events.last(where: {
            $0.type == .mouseClick && time >= $0.timestamp && time <= ($0.timestamp + 0.35)
        }) {
            clickProgress = (time - clickEv.timestamp) / 0.35
            isRight = (clickEv.button == .right)
        }
        
        return (finalPos, type, clickProgress, isRight, opacity)
    }
    
    public static func renderCursorOverlayImage(
        cursorInfo: (position: CGPoint, type: CursorType, clickProgress: Double?, isRightClick: Bool, opacity: Double),
        cardSize: CGSize,
        scale: CGFloat
    ) -> CIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        let baseSize: CGFloat = 26.0 * scale
        let ripplePad: CGFloat = 36.0 * scale
        let tileSize: CGFloat = max(120.0, (baseSize + ripplePad) * 2.0)
        let intTile = Int(ceil(tileSize))
        
        guard let context = CGContext(
            data: nil,
            width: intTile,
            height: intTile,
            bitsPerComponent: 8,
            bytesPerRow: intTile * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        context.clear(CGRect(x: 0, y: 0, width: intTile, height: intTile))
        context.saveGState()
        context.setAlpha(CGFloat(cursorInfo.opacity))
        
        let center = CGPoint(x: CGFloat(intTile) / 2.0, y: CGFloat(intTile) / 2.0)
        CustomCursorRenderer.drawCursor(
            in: context,
            at: center,
            type: cursorInfo.type,
            size: baseSize,
            clickProgress: cursorInfo.clickProgress,
            isRightClick: cursorInfo.isRightClick
        )
        context.restoreGState()
        
        guard let cgImage = context.makeImage() else { return nil }
        let rawCI = CIImage(cgImage: cgImage)
        
        let targetX = cursorInfo.position.x * cardSize.width - (CGFloat(intTile) / 2.0)
        let targetY = (1.0 - cursorInfo.position.y) * cardSize.height - (CGFloat(intTile) / 2.0)
        
        return rawCI.transformed(by: CGAffineTransform(translationX: targetX, y: targetY))
    }
}
