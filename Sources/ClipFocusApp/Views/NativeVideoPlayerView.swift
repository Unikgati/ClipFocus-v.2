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
    private let lightingLayer = CAGradientLayer()
    
    private var currentScale: CGFloat = 1.0
    private var currentFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var currentPositionX: CGFloat = 0.0
    private var currentPositionY: CGFloat = 0.0
    
    private var is3DEnabled: Bool = true
    private var pitch: Double = 0.0
    private var yaw: Double = 0.0
    private var roll: Double = 0.0
    private var shadowRadius: CGFloat = 24.0
    
    override public var isFlipped: Bool {
        return true
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
        
        // Root layer defines smooth, bold 3D cinematic perspective matching FocuSee / Screen Studio
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 480.0 // Strong cinematic perspective focal distance with rich depth foreshortening
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
        
        // 3D Lighting & specular gradient overlay for realistic depth & sheen
        lightingLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.24).cgColor
        ]
        lightingLayer.locations = [0.0, 0.45, 1.0]
        lightingLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        lightingLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        lightingLayer.opacity = 0.0
        
        clipLayer.addSublayer(playerLayer)
        clipLayer.addSublayer(lightingLayer)
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
        lightingLayer.frame = clipLayer.bounds
        updateCardTransform()
        CATransaction.commit()
    }
    
    private func updateCardTransform() {
        let scale = max(1.0, currentScale)
        let fx = max(0.0, min(1.0, currentFocusPoint.x))
        let fy = max(0.0, min(1.0, currentFocusPoint.y))
        
        // Exact viewport translation: centers the camera focus point smoothly
        let transX = (0.5 - fx) * bounds.width * scale + (currentPositionX * 2.0)
        let transY = (0.5 - fy) * bounds.height * scale + (currentPositionY * 2.0)
        
        // Dynamic 3D depth translation (Z-elevation) brings card closer to user in 3D space
        let elevationZ: CGFloat = is3DEnabled ? min(120.0, (scale - 1.0) * 65.0) : 0.0
        
        var cardTransform = CATransform3DIdentity
        cardTransform = CATransform3DTranslate(cardTransform, transX, transY, elevationZ)
        cardTransform = CATransform3DScale(cardTransform, scale, scale, 1.0)
        
        if is3DEnabled && (abs(pitch) > 0.05 || abs(yaw) > 0.05 || abs(roll) > 0.05) {
            let radPitch = CGFloat(pitch * .pi / 180.0)
            let radYaw = CGFloat(yaw * .pi / 180.0)
            let radRoll = CGFloat(roll * .pi / 180.0)
            
            cardTransform = CATransform3DRotate(cardTransform, radPitch, 1, 0, 0)
            cardTransform = CATransform3DRotate(cardTransform, radYaw, 0, 1, 0)
            cardTransform = CATransform3DRotate(cardTransform, radRoll, 0, 0, 1)
            
            // Dynamic 3D specular lighting angle shift
            let lightAngle = atan2(pitch, yaw)
            let lx0 = 0.5 - cos(lightAngle) * 0.5
            let ly0 = 0.5 - sin(lightAngle) * 0.5
            let lx1 = 0.5 + cos(lightAngle) * 0.5
            let ly1 = 0.5 + sin(lightAngle) * 0.5
            lightingLayer.startPoint = CGPoint(x: lx0, y: ly0)
            lightingLayer.endPoint = CGPoint(x: lx1, y: ly1)
            let tiltMag = min(1.0, hypot(pitch / 25.0, yaw / 25.0))
            lightingLayer.opacity = Float(tiltMag * 0.70)
            
            // Rich multi-directional dynamic drop shadow matching 3D angle
            let shadowX = CGFloat(-yaw * 1.8)
            let shadowY = CGFloat(20.0 + pitch * 1.5)
            contentLayer.shadowOffset = CGSize(width: shadowX, height: shadowY)
            contentLayer.shadowOpacity = Float(min(0.85, 0.55 + (scale - 1.0) * 0.15))
            contentLayer.shadowRadius = CGFloat(shadowRadius * (1.2 + (scale - 1.0) * 0.55))
        } else {
            lightingLayer.opacity = 0.0
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
        is3DEnabled: Bool
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
        is3DEnabled: Bool = true
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
            is3DEnabled: is3DEnabled
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
            is3DEnabled: is3DEnabled
        )
    }
}
