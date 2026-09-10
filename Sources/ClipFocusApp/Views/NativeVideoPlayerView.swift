import SwiftUI
import AVFoundation
import AppKit

/// High-performance 3D Cinematic Perspective Video Player
/// Directly leverages AVPlayerLayer and CoreAnimation CATransform3D (m34 perspective)
/// to achieve true Screen Studio / FocuSee 3D perspective tilts and razor-sharp zoom focusing on macOS.
public final class CinematicPlayerNSView: NSView {
    public let playerLayer = AVPlayerLayer()
    private let contentLayer = CALayer()
    private let clipLayer = CALayer()
    
    private var currentScale: CGFloat = 1.0
    private var currentFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var currentPositionX: CGFloat = 0.0
    private var currentPositionY: CGFloat = 0.0
    
    private var is3DEnabled: Bool = true
    private var pitch: Double = 0.0
    private var yaw: Double = 0.0
    private var roll: Double = 0.0
    private var shadowRadius: CGFloat = 24.0
    
    public var previewScale: CGFloat = 1.0
    
    override public var isFlipped: Bool {
        return true
    }
    
    override public func hitTest(_ point: NSPoint) -> NSView? {
        // Crucial: Return nil so the player layer never intercepts or blocks clicks on sidebar or controls
        return nil
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 850.0
        layer?.sublayerTransform = perspective
        
        // Content layer represents the floating video card with 3D tilt and soft drop shadow
        contentLayer.masksToBounds = false
        contentLayer.backgroundColor = NSColor.clear.cgColor
        contentLayer.shadowColor = NSColor.black.cgColor
        contentLayer.shadowOpacity = 0.55
        contentLayer.shadowRadius = 32
        contentLayer.shadowOffset = CGSize(width: 0, height: 16)
        
        // Clip layer ensures rounded corners and clean border wrap tightly around the video
        clipLayer.masksToBounds = true
        clipLayer.backgroundColor = NSColor.clear.cgColor
        clipLayer.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        clipLayer.borderWidth = 1.2
        
        // Video layer: fills the card exactly
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.masksToBounds = true
        playerLayer.backgroundColor = NSColor.clear.cgColor
        
        clipLayer.addSublayer(playerLayer)
        contentLayer.addSublayer(clipLayer)
        layer?.addSublayer(contentLayer)
    }
    
    override public func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.bounds = bounds
        contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        clipLayer.frame = contentLayer.bounds
        playerLayer.frame = clipLayer.bounds
        updateCardTransform()
        CATransaction.commit()
    }
    
    private func updateCardTransform() {
        var perspective = CATransform3DIdentity
        let effectiveFocalDistance = 850.0 * previewScale
        perspective.m34 = -1.0 / effectiveFocalDistance
        layer?.sublayerTransform = perspective
        
        let scale = max(1.0, currentScale)
        let fx = max(0.0, min(1.0, currentFocusPoint.x))
        let fy = max(0.0, min(1.0, currentFocusPoint.y))
        
        // Exact viewport translation: centers the camera focus point smoothly
        let panScale = bounds.width / 850.0
        let transX = (0.5 - fx) * bounds.width * scale + (currentPositionX * 2.0) * panScale
        let transY = (0.5 - fy) * bounds.height * scale + (currentPositionY * 2.0) * panScale
        
        // Smooth continuous 3D tilt factor without non-differentiable clamp kinks
        let tiltMagnitude = hypot(pitch / 16.0, yaw / 16.0)
        let tiltRatio = tanh(tiltMagnitude)
        
        // Dynamic 3D depth translation (Z-elevation) scaling proportionally with preview canvas
        let elevationZ: CGFloat = (scale - 1.0) * 45.0 * CGFloat(tiltRatio) * previewScale
        
        var cardTransform = CATransform3DIdentity
        cardTransform = CATransform3DTranslate(cardTransform, transX, transY, elevationZ)
        cardTransform = CATransform3DScale(cardTransform, scale, scale, 1.0)
        
        if abs(pitch) > 0.02 || abs(yaw) > 0.02 || abs(roll) > 0.02 {
            let radPitch = CGFloat(pitch * .pi / 180.0)
            let radYaw = CGFloat(yaw * .pi / 180.0)
            let radRoll = CGFloat(roll * .pi / 180.0)
            
            cardTransform = CATransform3DRotate(cardTransform, radPitch, 1, 0, 0)
            cardTransform = CATransform3DRotate(cardTransform, radYaw, 0, 1, 0)
            cardTransform = CATransform3DRotate(cardTransform, radRoll, 0, 0, 1)
            
            // Rich continuous multi-directional drop shadow matching 3D angle
            let shadowX = CGFloat(-yaw * 1.5) * CGFloat(tiltRatio)
            let shadowY = CGFloat(12.0 + (pitch * 1.2) * tiltRatio)
            contentLayer.shadowOffset = CGSize(width: shadowX, height: shadowY)
            contentLayer.shadowOpacity = Float(0.45 + (tiltRatio * 0.20))
            contentLayer.shadowRadius = CGFloat(shadowRadius + (tiltRatio * 12.0))
        } else {
            contentLayer.shadowOffset = CGSize(width: 0, height: 12)
            contentLayer.shadowOpacity = 0.45
            contentLayer.shadowRadius = CGFloat(shadowRadius)
        }
        
        contentLayer.transform = cardTransform
    }
    
    public func update(
        player: AVPlayer?,
        scale: CGFloat,
        focusPoint: CGPoint,
        positionOffsetX: CGFloat = 0.0,
        positionOffsetY: CGFloat = 0.0,
        pitch: Double,
        yaw: Double,
        roll: Double,
        cornerRadius: CGFloat,
        shadowRadius: CGFloat,
        is3DEnabled: Bool,
        previewScale: CGFloat = 1.0
    ) {
        if playerLayer.player !== player {
            playerLayer.player = player
        }
        
        self.currentScale = scale
        self.currentFocusPoint = focusPoint
        self.currentPositionX = positionOffsetX
        self.currentPositionY = positionOffsetY
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.shadowRadius = shadowRadius
        self.is3DEnabled = is3DEnabled
        self.previewScale = previewScale
        
        clipLayer.cornerRadius = cornerRadius
        playerLayer.cornerRadius = cornerRadius
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateCardTransform()
        CATransaction.commit()
    }
}

public struct NativeVideoPlayerView: NSViewRepresentable {
    public let player: AVPlayer
    public var scale: CGFloat = 1.0
    public var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    public var positionOffsetX: CGFloat = 0.0
    public var positionOffsetY: CGFloat = 0.0
    public var pitch: Double = 0.0
    public var yaw: Double = 0.0
    public var roll: Double = 0.0
    public var cornerRadius: CGFloat = 12.0
    public var shadowRadius: CGFloat = 20.0
    public var is3DEnabled: Bool = true
    public var previewScale: CGFloat = 1.0

    public init(
        player: AVPlayer,
        scale: CGFloat = 1.0,
        focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        positionOffsetX: CGFloat = 0.0,
        positionOffsetY: CGFloat = 0.0,
        pitch: Double = 0.0,
        yaw: Double = 0.0,
        roll: Double = 0.0,
        cornerRadius: CGFloat = 12.0,
        shadowRadius: CGFloat = 20.0,
        is3DEnabled: Bool = true,
        previewScale: CGFloat = 1.0
    ) {
        self.player = player
        self.scale = scale
        self.focusPoint = focusPoint
        self.positionOffsetX = positionOffsetX
        self.positionOffsetY = positionOffsetY
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.is3DEnabled = is3DEnabled
        self.previewScale = previewScale
    }

    public func makeNSView(context: Context) -> CinematicPlayerNSView {
        let view = CinematicPlayerNSView()
        view.update(
            player: player,
            scale: scale,
            focusPoint: focusPoint,
            positionOffsetX: positionOffsetX,
            positionOffsetY: positionOffsetY,
            pitch: pitch,
            yaw: yaw,
            roll: roll,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            is3DEnabled: is3DEnabled,
            previewScale: previewScale
        )
        return view
    }

    public func updateNSView(_ nsView: CinematicPlayerNSView, context: Context) {
        nsView.update(
            player: player,
            scale: scale,
            focusPoint: focusPoint,
            positionOffsetX: positionOffsetX,
            positionOffsetY: positionOffsetY,
            pitch: pitch,
            yaw: yaw,
            roll: roll,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            is3DEnabled: is3DEnabled,
            previewScale: previewScale
        )
    }
}
