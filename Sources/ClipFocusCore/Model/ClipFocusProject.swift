import Foundation
import CoreGraphics

/// Canvas aspect ratio presets for various target platforms
public enum CanvasAspectRatio: String, Codable, Sendable, CaseIterable {
    case widescreen16x9 = "16:9" // YouTube, Desktop, TV
    case vertical9x16 = "9:16"   // TikTok, Instagram Reels, YouTube Shorts
    case square1x1 = "1:1"       // Instagram Feed, LinkedIn
    case standard4x3 = "4:3"     // Classic presentations
    case ultraWide21x9 = "21:9"  // Cinematic ultrawide
    
    public var ratioValue: CGFloat {
        switch self {
        case .widescreen16x9: return 16.0 / 9.0
        case .vertical9x16: return 9.0 / 16.0
        case .square1x1: return 1.0
        case .standard4x3: return 4.0 / 3.0
        case .ultraWide21x9: return 21.0 / 9.0
        }
    }
}

/// Canvas background styling options
public struct CanvasBackgroundStyle: Codable, Sendable {
    public enum StyleType: String, Codable, Sendable {
        case gradient
        case solidColor
        case wallpaperImage
        case blurredScreen
    }
    
    public var type: StyleType
    public var primaryColorHex: String
    public var secondaryColorHex: String?
    public var gradientAngleDegrees: Double
    public var padding: CGFloat // Canvas inset padding in pixels
    public var cornerRadius: CGFloat // Window corner roundness
    public var shadowRadius: CGFloat // Window drop shadow blur
    public var shadowOpacity: Double

    public init(
        type: StyleType = .gradient,
        primaryColorHex: String = "#6366F1",
        secondaryColorHex: String? = "#EC4899",
        gradientAngleDegrees: Double = 135.0,
        padding: CGFloat = 48.0,
        cornerRadius: CGFloat = 16.0,
        shadowRadius: CGFloat = 32.0,
        shadowOpacity: Double = 0.35
    ) {
        self.type = type
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.gradientAngleDegrees = gradientAngleDegrees
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
    }
}

/// Cursor presentation styling
public struct CursorVisualSettings: Codable, Sendable {
    public enum CursorStyle: String, Codable, Sendable {
        case macOSDefault = "macos_default"
        case modernSmooth = "modern_smooth"
        case neonGlow = "neon_glow"
        case circleHighlight = "circle_highlight"
    }

    public var style: CursorStyle
    public var sizeScale: CGFloat // 1.0 = normal, 1.5 = magnified
    public var clickRippleEnabled: Bool
    public var clickSoundEnabled: Bool
    public var autoHideWhenIdle: Bool
    public var idleHideDelaySeconds: TimeInterval

    public init(
        style: CursorStyle = .modernSmooth,
        sizeScale: CGFloat = 1.25,
        clickRippleEnabled: Bool = true,
        clickSoundEnabled: Bool = false,
        autoHideWhenIdle: Bool = true,
        idleHideDelaySeconds: TimeInterval = 2.0
    ) {
        self.style = style
        self.sizeScale = sizeScale
        self.clickRippleEnabled = clickRippleEnabled
        self.clickSoundEnabled = clickSoundEnabled
        self.autoHideWhenIdle = autoHideWhenIdle
        self.idleHideDelaySeconds = idleHideDelaySeconds
    }
}

/// Webcam Picture-in-Picture layout settings
public struct WebcamLayoutSettings: Codable, Sendable {
    public enum Position: String, Codable, Sendable {
        case bottomRight = "bottom_right"
        case bottomLeft = "bottom_left"
        case topRight = "top_right"
        case topLeft = "top_left"
        case hidden = "hidden"
    }

    public enum Shape: String, Codable, Sendable {
        case circle
        case roundedRect
        case square
    }

    public var isEnabled: Bool
    public var position: Position
    public var shape: Shape
    public var sizeScale: CGFloat
    public var borderWidth: CGFloat
    public var borderColorHex: String

    public init(
        isEnabled: Bool = true,
        position: Position = .bottomRight,
        shape: Shape = .circle,
        sizeScale: CGFloat = 0.22,
        borderWidth: CGFloat = 4.0,
        borderColorHex: String = "#FFFFFF"
    ) {
        self.isEnabled = isEnabled
        self.position = position
        self.shape = shape
        self.sizeScale = sizeScale
        self.borderWidth = borderWidth
        self.borderColorHex = borderColorHex
    }
}

/// Subtitle entry for captions
public struct SubtitleSegment: Codable, Identifiable, Sendable {
    public let id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String

    public init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

/// The master project container representing a recording and all its non-destructive edits
public struct ClipFocusProject: Codable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var rawVideoFilename: String
    public var rawAudioFilename: String?
    public var rawWebcamFilename: String?
    public var telemetryFilename: String
    
    // Video Canvas & Layout configuration
    public var aspectRatio: CanvasAspectRatio
    public var backgroundStyle: CanvasBackgroundStyle
    public var cursorSettings: CursorVisualSettings
    public var webcamSettings: WebcamLayoutSettings
    
    // Non-destructive timeline keyframes & annotations
    public var zoomKeyframes: [ZoomKeyframe]
    public var subtitles: [SubtitleSegment]
    public var videoSegments: [MediaClipSegment]
    public var audioSegments: [MediaClipSegment]
    
    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        rawVideoFilename: String,
        rawAudioFilename: String? = nil,
        rawWebcamFilename: String? = nil,
        telemetryFilename: String,
        aspectRatio: CanvasAspectRatio = .widescreen16x9,
        backgroundStyle: CanvasBackgroundStyle = CanvasBackgroundStyle(),
        cursorSettings: CursorVisualSettings = CursorVisualSettings(),
        webcamSettings: WebcamLayoutSettings = WebcamLayoutSettings(),
        zoomKeyframes: [ZoomKeyframe] = [],
        subtitles: [SubtitleSegment] = [],
        videoSegments: [MediaClipSegment] = [],
        audioSegments: [MediaClipSegment] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.rawVideoFilename = rawVideoFilename
        self.rawAudioFilename = rawAudioFilename
        self.rawWebcamFilename = rawWebcamFilename
        self.telemetryFilename = telemetryFilename
        self.aspectRatio = aspectRatio
        self.backgroundStyle = backgroundStyle
        self.cursorSettings = cursorSettings
        self.webcamSettings = webcamSettings
        self.zoomKeyframes = zoomKeyframes
        self.subtitles = subtitles
        self.videoSegments = videoSegments
        self.audioSegments = audioSegments
    }
}
