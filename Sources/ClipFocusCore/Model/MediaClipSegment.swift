import Foundation

/// Track type representing media category on the timeline
public enum TimelineTrackType: String, Codable, Sendable, CaseIterable {
    case video = "video"
    case zoom = "zoom"
    case audio = "audio"
}

/// Represents an independent cut/trimmed segment of video or audio on the multi-track timeline
public struct MediaClipSegment: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var trackType: TimelineTrackType
    public var name: String
    public var sourceStartTime: TimeInterval    // Offset into original source media asset
    public var timelineStartTime: TimeInterval  // Position on timeline ruler
    public var duration: TimeInterval           // Visible duration
    public var isMuted: Bool
    public var volume: Double                   // 0.0 to 2.0 (1.0 = 100%)
    
    public init(
        id: UUID = UUID(),
        trackType: TimelineTrackType = .video,
        name: String = "Clip",
        sourceStartTime: TimeInterval = 0.0,
        timelineStartTime: TimeInterval = 0.0,
        duration: TimeInterval,
        isMuted: Bool = false,
        volume: Double = 1.0
    ) {
        self.id = id
        self.trackType = trackType
        self.name = name
        self.sourceStartTime = sourceStartTime
        self.timelineStartTime = timelineStartTime
        self.duration = duration
        self.isMuted = isMuted
        self.volume = volume
    }
    
    public var timelineEndTime: TimeInterval {
        return timelineStartTime + duration
    }
    
    public var sourceEndTime: TimeInterval {
        return sourceStartTime + duration
    }
}
