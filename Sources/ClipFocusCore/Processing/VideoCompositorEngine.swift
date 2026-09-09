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
        disableZoom: Bool = false
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
            
            // Dynamic Zoom Scale and Viewport Translation:
            // Centering the focus point:
            // transX = (0.5 - fx) * baseCardW * zoomScale + (viewport.positionOffsetX * 2.0)
            // In CI (where Y=0 is at bottom), (0.5 - fy_ci) = (fy - 0.5):
            let transX = (0.5 - fx) * baseCardW * zoomScale + (viewport.positionOffsetX * 2.0)
            let transY = (0.5 - fy_ci) * baseCardH * zoomScale - (viewport.positionOffsetY * 2.0)
            
            let scaledCardW = baseCardW * zoomScale
            let scaledCardH = baseCardH * zoomScale
            let cardCenterX = renderSize.width * 0.5 + transX
            let cardCenterY = renderSize.height * 0.5 + transY
            
            let cardRect = CGRect(
                x: cardCenterX - scaledCardW * 0.5,
                y: cardCenterY - scaledCardH * 0.5,
                width: scaledCardW,
                height: scaledCardH
            )
            
            // 4. Transform Source Video to Fill Dynamic Card Rect
            var videoTrans = CGAffineTransform(translationX: cardRect.origin.x, y: cardRect.origin.y)
            videoTrans = videoTrans.scaledBy(x: cardRect.width / srcW, y: cardRect.height / srcH)
            
            let transformedVideo = sourceImage.transformed(by: videoTrans)
            
            // 5. Generate Card Mask with Rounded Corners (scaled with zoom)
            let cardCornerRadius = config.cornerRadius * (1.0 + (zoomScale - 1.0) * 0.25)
            let rectGen = CIFilter(name: "CIRoundedRectangleGenerator")!
            rectGen.setValue(CIVector(cgRect: cardRect), forKey: "inputExtent")
            rectGen.setValue(cardCornerRadius, forKey: "inputRadius")
            rectGen.setValue(CIColor.white, forKey: "inputColor")
            
            guard let cardMask = rectGen.outputImage else {
                request.finish(with: sourceImage, context: nil)
                return
            }
            
            // Clip video cleanly inside floating rounded card
            let blend = CIFilter(name: "CIBlendWithMask")!
            blend.setValue(transformedVideo, forKey: kCIInputImageKey)
            blend.setValue(cardMask, forKey: kCIInputMaskImageKey)
            blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            
            guard var finalCard = blend.outputImage else {
                request.finish(with: sourceImage, context: nil)
                return
            }
            
            // 6. 3D Perspective Tilt (Screen Studio / FocuSee style)
            let pitch = viewport.pitch * config.tiltIntensity
            let yaw = viewport.yaw * config.tiltIntensity
            let roll = viewport.roll
            let tiltMagnitude = hypot(pitch / 16.0, yaw / 16.0)
            let tiltRatio = min(1.0, tiltMagnitude)
            
            var pBL = CGPoint(x: cardRect.minX, y: cardRect.minY)
            var pBR = CGPoint(x: cardRect.maxX, y: cardRect.minY)
            var pTR = CGPoint(x: cardRect.maxX, y: cardRect.maxY)
            var pTL = CGPoint(x: cardRect.minX, y: cardRect.maxY)
            let isTilted = abs(pitch) > 0.05 || abs(yaw) > 0.05 || abs(roll) > 0.05
            
            if isTilted {
                let radPitch = pitch * .pi / 180.0
                let radYaw = yaw * .pi / 180.0
                let radRoll = roll * .pi / 180.0
                
                let hw = cardRect.width * 0.5
                let hh = cardRect.height * 0.5
                let cx = cardRect.midX
                let cy = cardRect.midY
                
                let depthFactor = 0.32
                let pitchSin = sin(radPitch) * depthFactor
                let yawSin = sin(radYaw) * depthFactor
                
                pBL = CGPoint(x: cx - hw * (1.0 + pitchSin), y: cy - hh * (1.0 - yawSin))
                pBR = CGPoint(x: cx + hw * (1.0 + pitchSin), y: cy - hh * (1.0 + yawSin))
                pTR = CGPoint(x: cx + hw * (1.0 - pitchSin), y: cy + hh * (1.0 + yawSin))
                pTL = CGPoint(x: cx - hw * (1.0 - pitchSin), y: cy + hh * (1.0 - yawSin))
                
                if abs(radRoll) > 0.01 {
                    let cosR = cos(radRoll)
                    let sinR = sin(radRoll)
                    func rotatePt(_ p: CGPoint) -> CGPoint {
                        let dx = p.x - cx
                        let dy = p.y - cy
                        return CGPoint(x: cx + dx * cosR - dy * sinR, y: cy + dx * sinR + dy * cosR)
                    }
                    pBL = rotatePt(pBL)
                    pBR = rotatePt(pBR)
                    pTR = rotatePt(pTR)
                    pTL = rotatePt(pTL)
                }
                
                let persp = CIFilter(name: "CIPerspectiveTransform")!
                persp.setValue(finalCard, forKey: kCIInputImageKey)
                persp.setValue(CIVector(cgPoint: pTL), forKey: "inputTopLeft")
                persp.setValue(CIVector(cgPoint: pTR), forKey: "inputTopRight")
                persp.setValue(CIVector(cgPoint: pBR), forKey: "inputBottomRight")
                persp.setValue(CIVector(cgPoint: pBL), forKey: "inputBottomLeft")
                
                if let perspCard = persp.outputImage {
                    finalCard = perspCard
                }
            }
            
            // 7. Dynamic Drop Shadow matching 3D angle and zoom scale
            var compositeCard = finalCard
            if config.shadowRadius > 2.0 {
                let shadowGen = CIFilter(name: "CIRoundedRectangleGenerator")!
                shadowGen.setValue(CIVector(cgRect: cardRect), forKey: "inputExtent")
                shadowGen.setValue(cardCornerRadius, forKey: "inputRadius")
                let shadowAlpha = CGFloat(0.45 + (tiltRatio * 0.20))
                shadowGen.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: shadowAlpha), forKey: "inputColor")
                
                if var shadowImage = shadowGen.outputImage {
                    // If 3D tilted, tilt the shadow shape in perspective
                    if isTilted {
                        let perspShadow = CIFilter(name: "CIPerspectiveTransform")!
                        perspShadow.setValue(shadowImage, forKey: kCIInputImageKey)
                        perspShadow.setValue(CIVector(cgPoint: pTL), forKey: "inputTopLeft")
                        perspShadow.setValue(CIVector(cgPoint: pTR), forKey: "inputTopRight")
                        perspShadow.setValue(CIVector(cgPoint: pBR), forKey: "inputBottomRight")
                        perspShadow.setValue(CIVector(cgPoint: pBL), forKey: "inputBottomLeft")
                        if let pShadow = perspShadow.outputImage {
                            shadowImage = pShadow
                        }
                    }
                    
                    let blur = CIFilter(name: "CIGaussianBlur")!
                    blur.setValue(shadowImage, forKey: kCIInputImageKey)
                    let effectiveShadowRadius = (config.shadowRadius + (CGFloat(tiltRatio) * 12.0)) * (1.0 + (zoomScale - 1.0) * 0.25)
                    blur.setValue(effectiveShadowRadius, forKey: kCIInputRadiusKey)
                    
                    if let blurredShadow = blur.outputImage {
                        let shadowShiftX = CGFloat(-yaw * 1.5) * CGFloat(tiltRatio) * (zoomScale * 0.8)
                        let shadowShiftY = CGFloat(-config.shadowRadius * 0.35 - (pitch * 1.2 * tiltRatio)) * (zoomScale * 0.8)
                        let shadowShift = CGAffineTransform(translationX: shadowShiftX, y: shadowShiftY)
                        let shiftedShadow = blurredShadow.transformed(by: shadowShift)
                        compositeCard = finalCard.composited(over: shiftedShadow)
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
}
