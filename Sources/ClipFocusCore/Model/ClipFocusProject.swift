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
    public var schemaVersion: Int
    public var appVersion: String
    public var createdAt: Date
    public var updatedAt: Date
    public var duration: TimeInterval
    
    // Asset reference and relinking data
    public var rawVideoFilename: String
    public var relativeVideoPath: String?
    public var videoFileSize: Int64?
    public var rawAudioFilename: String?
    public var rawWebcamFilename: String?
    public var telemetryFilename: String
    public var embeddedTelemetry: [TelemetryEvent]?
    
    // Video Canvas & Layout configuration
    public var aspectRatio: CanvasAspectRatio
    public var canvasRatioString: String
    public var exportResolution: String
    public var backgroundStyle: CanvasBackgroundStyle
    public var canvasPadding: CGFloat
    public var canvasCornerRadius: CGFloat
    public var canvasShadowRadius: CGFloat
    public var canvasShadowOpacity: Double
    public var activeBackgroundIndex: Int
    public var activeColorIndex: Int?
    public var tiltIntensity: Double
    public var disableZoom: Bool
    
    public var cursorSettings: CursorVisualSettings
    public var webcamSettings: WebcamLayoutSettings
    
    // Audio & Track Visibility States
    public var isAudioMuted: Bool
    public var audioVolume: Double
    public var isVideoTrackHidden: Bool
    public var isZoomTrackHidden: Bool
    
    // Playhead & Timeline state
    public var currentTime: Double
    public var timelineZoomScale: CGFloat
    
    // Non-destructive timeline keyframes & annotations
    public var zoomKeyframes: [ZoomKeyframe]
    public var subtitles: [SubtitleSegment]
    public var videoSegments: [MediaClipSegment]
    public var audioSegments: [MediaClipSegment]
    
    public init(
        id: UUID = UUID(),
        title: String,
        schemaVersion: Int = 1,
        appVersion: String = "1.0.0",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        duration: TimeInterval,
        rawVideoFilename: String,
        relativeVideoPath: String? = nil,
        videoFileSize: Int64? = nil,
        rawAudioFilename: String? = nil,
        rawWebcamFilename: String? = nil,
        telemetryFilename: String = "",
        embeddedTelemetry: [TelemetryEvent]? = nil,
        aspectRatio: CanvasAspectRatio = .widescreen16x9,
        canvasRatioString: String = "16:9",
        exportResolution: String = "1080p",
        backgroundStyle: CanvasBackgroundStyle = CanvasBackgroundStyle(),
        canvasPadding: CGFloat = 48.0,
        canvasCornerRadius: CGFloat = 16.0,
        canvasShadowRadius: CGFloat = 32.0,
        canvasShadowOpacity: Double = 0.35,
        activeBackgroundIndex: Int = 0,
        activeColorIndex: Int? = nil,
        tiltIntensity: Double = 1.0,
        disableZoom: Bool = false,
        cursorSettings: CursorVisualSettings = CursorVisualSettings(),
        webcamSettings: WebcamLayoutSettings = WebcamLayoutSettings(),
        isAudioMuted: Bool = false,
        audioVolume: Double = 1.0,
        isVideoTrackHidden: Bool = false,
        isZoomTrackHidden: Bool = false,
        currentTime: Double = 0.0,
        timelineZoomScale: CGFloat = 1.0,
        zoomKeyframes: [ZoomKeyframe] = [],
        subtitles: [SubtitleSegment] = [],
        videoSegments: [MediaClipSegment] = [],
        audioSegments: [MediaClipSegment] = []
    ) {
        self.id = id
        self.title = title
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.rawVideoFilename = rawVideoFilename
        self.relativeVideoPath = relativeVideoPath
        self.videoFileSize = videoFileSize
        self.rawAudioFilename = rawAudioFilename
        self.rawWebcamFilename = rawWebcamFilename
        self.telemetryFilename = telemetryFilename
        self.embeddedTelemetry = embeddedTelemetry
        self.aspectRatio = aspectRatio
        self.canvasRatioString = canvasRatioString
        self.exportResolution = exportResolution
        self.backgroundStyle = backgroundStyle
        self.canvasPadding = canvasPadding
        self.canvasCornerRadius = canvasCornerRadius
        self.canvasShadowRadius = canvasShadowRadius
        self.canvasShadowOpacity = canvasShadowOpacity
        self.activeBackgroundIndex = activeBackgroundIndex
        self.activeColorIndex = activeColorIndex
        self.tiltIntensity = tiltIntensity
        self.disableZoom = disableZoom
        self.cursorSettings = cursorSettings
        self.webcamSettings = webcamSettings
        self.isAudioMuted = isAudioMuted
        self.audioVolume = audioVolume
        self.isVideoTrackHidden = isVideoTrackHidden
        self.isZoomTrackHidden = isZoomTrackHidden
        self.currentTime = currentTime
        self.timelineZoomScale = timelineZoomScale
        self.zoomKeyframes = zoomKeyframes
        self.subtitles = subtitles
        self.videoSegments = videoSegments
        self.audioSegments = audioSegments
    }
    
    // Custom Decodable initializer to gracefully handle schema additions
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Project"
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "1.0.0"
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 1.0
        
        self.rawVideoFilename = try container.decodeIfPresent(String.self, forKey: .rawVideoFilename) ?? ""
        self.relativeVideoPath = try container.decodeIfPresent(String.self, forKey: .relativeVideoPath)
        self.videoFileSize = try container.decodeIfPresent(Int64.self, forKey: .videoFileSize)
        self.rawAudioFilename = try container.decodeIfPresent(String.self, forKey: .rawAudioFilename)
        self.rawWebcamFilename = try container.decodeIfPresent(String.self, forKey: .rawWebcamFilename)
        self.telemetryFilename = try container.decodeIfPresent(String.self, forKey: .telemetryFilename) ?? ""
        self.embeddedTelemetry = try container.decodeIfPresent([TelemetryEvent].self, forKey: .embeddedTelemetry)
        
        self.aspectRatio = try container.decodeIfPresent(CanvasAspectRatio.self, forKey: .aspectRatio) ?? .widescreen16x9
        self.canvasRatioString = try container.decodeIfPresent(String.self, forKey: .canvasRatioString) ?? "16:9"
        self.exportResolution = try container.decodeIfPresent(String.self, forKey: .exportResolution) ?? "1080p"
        self.backgroundStyle = try container.decodeIfPresent(CanvasBackgroundStyle.self, forKey: .backgroundStyle) ?? CanvasBackgroundStyle()
        self.canvasPadding = try container.decodeIfPresent(CGFloat.self, forKey: .canvasPadding) ?? 48.0
        self.canvasCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .canvasCornerRadius) ?? 16.0
        self.canvasShadowRadius = try container.decodeIfPresent(CGFloat.self, forKey: .canvasShadowRadius) ?? 32.0
        self.canvasShadowOpacity = try container.decodeIfPresent(Double.self, forKey: .canvasShadowOpacity) ?? 0.35
        self.activeBackgroundIndex = try container.decodeIfPresent(Int.self, forKey: .activeBackgroundIndex) ?? 0
        self.activeColorIndex = try container.decodeIfPresent(Int.self, forKey: .activeColorIndex)
        self.tiltIntensity = try container.decodeIfPresent(Double.self, forKey: .tiltIntensity) ?? 1.0
        self.disableZoom = try container.decodeIfPresent(Bool.self, forKey: .disableZoom) ?? false
        
        self.cursorSettings = try container.decodeIfPresent(CursorVisualSettings.self, forKey: .cursorSettings) ?? CursorVisualSettings()
        self.webcamSettings = try container.decodeIfPresent(WebcamLayoutSettings.self, forKey: .webcamSettings) ?? WebcamLayoutSettings()
        
        self.isAudioMuted = try container.decodeIfPresent(Bool.self, forKey: .isAudioMuted) ?? false
        self.audioVolume = try container.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 1.0
        self.isVideoTrackHidden = try container.decodeIfPresent(Bool.self, forKey: .isVideoTrackHidden) ?? false
        self.isZoomTrackHidden = try container.decodeIfPresent(Bool.self, forKey: .isZoomTrackHidden) ?? false
        
        self.currentTime = try container.decodeIfPresent(Double.self, forKey: .currentTime) ?? 0.0
        self.timelineZoomScale = try container.decodeIfPresent(CGFloat.self, forKey: .timelineZoomScale) ?? 1.0
        
        self.zoomKeyframes = try container.decodeIfPresent([ZoomKeyframe].self, forKey: .zoomKeyframes) ?? []
        self.subtitles = try container.decodeIfPresent([SubtitleSegment].self, forKey: .subtitles) ?? []
        self.videoSegments = try container.decodeIfPresent([MediaClipSegment].self, forKey: .videoSegments) ?? []
        self.audioSegments = try container.decodeIfPresent([MediaClipSegment].self, forKey: .audioSegments) ?? []
    }
    
    // MARK: - Smart Asset Relinking
    /// Resolves the video asset URL using a 3-tier intelligent lookup strategy:
    /// 1. Absolute path verification.
    /// 2. Relative path relative to the project document location.
    /// 3. Same folder sibling match based on filename.
    public func resolveVideoURL(relativeTo projectURL: URL) -> URL? {
        let fm = FileManager.default
        
        // Tier 1: Direct absolute path check
        if !rawVideoFilename.isEmpty && fm.fileExists(atPath: rawVideoFilename) {
            return URL(fileURLWithPath: rawVideoFilename)
        }
        
        let projectFolder = projectURL.deletingLastPathComponent()
        
        // Tier 2: Relative path check
        if let rel = relativeVideoPath, !rel.isEmpty {
            let candidate = projectFolder.appendingPathComponent(rel).standardizedFileURL
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        
        // Tier 3: Same directory sibling filename match
        let originalName = URL(fileURLWithPath: rawVideoFilename).lastPathComponent
        if !originalName.isEmpty {
            let siblingCandidate = projectFolder.appendingPathComponent(originalName)
            if fm.fileExists(atPath: siblingCandidate.path) {
                return siblingCandidate
            }
        }
        
        return nil
    }
    
    // MARK: - Serialization & Atomic File I/O
    public func encodeToData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    public static func decode(from data: Data) throws -> ClipFocusProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClipFocusProject.self, from: data)
    }
    
    /// Writes project file atomically to prevent data corruption during power loss or disk errors
    public func saveAtomic(to destinationURL: URL) throws {
        let data = try encodeToData()
        let fm = FileManager.default
        let folder = destinationURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        
        // Atomic write via safe temporary file
        let tempURL = folder.appendingPathComponent(".\(destinationURL.lastPathComponent).tmp_\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        
        if fm.fileExists(atPath: destinationURL.path) {
            _ = try fm.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try fm.moveItem(at: tempURL, to: destinationURL)
        }
    }
    
    public static func load(from url: URL) throws -> ClipFocusProject {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
