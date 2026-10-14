import Foundation
import CoreGraphics

/// Represents a detected audio silence, filler interval, or stagnant cursor inactivity recommended for automatic trimming
public struct TrimSegment: Codable, Identifiable, Sendable {
    public let id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var duration: TimeInterval { endTime - startTime }
    public var type: TrimType

    public enum TrimType: String, Codable, Sendable {
        case silence
        case fillerWord = "filler_word"
        case cursorInactivity = "cursor_inactivity"
        case userCustom = "user_custom"
    }

    public init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, type: TrimType = .silence) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.type = type
    }
}

/// Smart Cut Engine that analyzes audio energy to detect dead air and filler hesitations
public final class SmartCutEngine: @unchecked Sendable {
    
    public struct Config: Sendable {
        public var silenceThresholdDecibels: Float = -40.0
        public var minimumSilenceDuration: TimeInterval = 0.55
        public var paddingDuration: TimeInterval = 0.12 // Leave a slight breath margin before and after cuts
        
        public init() {}
    }
    
    public let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// Detects silent intervals from an array of RMS power audio samples
    /// - Parameters:
    ///   - samples: Array of decibel power readings (typically measured every 50ms)
    ///   - sampleInterval: Time in seconds between consecutive power measurements (e.g. 0.05s)
    public func detectSilences(powerSamples: [Float], sampleInterval: TimeInterval) -> [TrimSegment] {
        var silences: [TrimSegment] = []
        var inSilence = false
        var silenceStartIndex = 0
        
        for (index, power) in powerSamples.enumerated() {
            let isSilent = power <= config.silenceThresholdDecibels
            
            if isSilent && !inSilence {
                inSilence = true
                silenceStartIndex = index
            } else if !isSilent && inSilence {
                inSilence = false
                let duration = Double(index - silenceStartIndex) * sampleInterval
                if duration >= config.minimumSilenceDuration {
                    let rawStart = Double(silenceStartIndex) * sampleInterval
                    let rawEnd = Double(index) * sampleInterval
                    
                    // Apply breathing room padding
                    let safeStart = rawStart + config.paddingDuration
                    let safeEnd = max(safeStart, rawEnd - config.paddingDuration)
                    
                    if safeEnd > safeStart {
                        silences.append(TrimSegment(startTime: safeStart, endTime: safeEnd, type: .silence))
                    }
                }
            }
        }
        
        // Check edge case at the end of recording
        if inSilence {
            let duration = Double(powerSamples.count - silenceStartIndex) * sampleInterval
            if duration >= config.minimumSilenceDuration {
                let rawStart = Double(silenceStartIndex) * sampleInterval
                let rawEnd = Double(powerSamples.count) * sampleInterval
                let safeStart = rawStart + config.paddingDuration
                if rawEnd > safeStart {
                    silences.append(TrimSegment(startTime: safeStart, endTime: rawEnd, type: .silence))
                }
            }
        }
        
        return silences
    }
    
    /// Detects intervals where the cursor was stationary and no clicks, typing, or scrolls occurred.
    /// - Parameters:
    ///   - events: Array of recorded TelemetryEvent
    ///   - totalDuration: Total video duration in seconds
    ///   - minInactivityDuration: Threshold in seconds (e.g. 2.0s, 3.0s, 5.0s)
    ///   - movementTolerance: Max coordinate drift (normalized 0...1) considered stationary (default 0.012 ~ 20-25px)
    ///   - paddingDuration: Safe margin left before and after the cut (default 0.35s)
    /// - Returns: Array of TrimSegment recommended for automatic removal
    public func detectCursorInactivity(
        events: [TelemetryEvent],
        totalDuration: TimeInterval,
        minInactivityDuration: TimeInterval = 2.5,
        movementTolerance: CGFloat = 0.015,
        paddingDuration: TimeInterval = 0.35
    ) -> [TrimSegment] {
        guard totalDuration > minInactivityDuration, !events.isEmpty else { return [] }
        
        let step: TimeInterval = 0.1
        let totalSteps = max(1, Int(ceil(totalDuration / step)))
        var isActive = Array(repeating: false, count: totalSteps)
        
        // 1. Mark explicit interaction events (clicks, typing, scroll, drag)
        let padSteps = Int(ceil(paddingDuration / step))
        for event in events {
            let t = event.timestamp
            guard t >= 0 && t <= totalDuration else { continue }
            
            switch event.type {
            case .mouseClick, .mouseUp, .mouseDrag, .mouseScroll, .keyDown:
                let centerIdx = Int(t / step)
                let low = max(0, centerIdx - padSteps)
                let high = min(totalSteps - 1, centerIdx + padSteps)
                for i in low...high {
                    isActive[i] = true
                }
            case .mouseMove, .windowFocus:
                break
            }
        }
        
        // 2. Mark significant cursor movement
        let moveEvents = events.filter { $0.type == .mouseMove && $0.position != nil }.sorted { $0.timestamp < $1.timestamp }
        if moveEvents.count >= 2 {
            var anchor = moveEvents[0]
            for i in 1..<moveEvents.count {
                let curr = moveEvents[i]
                guard let p1 = anchor.position, let p2 = curr.position else {
                    anchor = curr
                    continue
                }
                let dt = curr.timestamp - anchor.timestamp
                let dist = hypot(p2.x - p1.x, p2.y - p1.y)
                
                if dist > movementTolerance {
                    let startIdx = max(0, Int(anchor.timestamp / step))
                    let endIdx = min(totalSteps - 1, Int(curr.timestamp / step))
                    for idx in startIdx...endIdx {
                        isActive[idx] = true
                    }
                    anchor = curr
                } else if dt > 0.5 {
                    anchor = curr
                }
            }
        }
        
        // 3. Collect contiguous inactive intervals
        var segments: [TrimSegment] = []
        var inInactive = false
        var inactiveStartStep = 0
        
        for i in 0..<totalSteps {
            if !isActive[i] && !inInactive {
                inInactive = true
                inactiveStartStep = i
            } else if isActive[i] && inInactive {
                inInactive = false
                let rawStart = Double(inactiveStartStep) * step
                let rawEnd = Double(i) * step
                let rawDuration = rawEnd - rawStart
                
                if rawDuration >= minInactivityDuration {
                    let safeStart = (inactiveStartStep == 0) ? 0.0 : (rawStart + paddingDuration)
                    let safeEnd = max(safeStart, rawEnd - paddingDuration)
                    if (safeEnd - safeStart) >= 0.5 {
                        segments.append(TrimSegment(startTime: safeStart, endTime: safeEnd, type: .cursorInactivity))
                    }
                }
            }
        }
        
        if inInactive {
            let rawStart = Double(inactiveStartStep) * step
            let rawEnd = totalDuration
            let rawDuration = rawEnd - rawStart
            if rawDuration >= minInactivityDuration {
                let safeStart = (inactiveStartStep == 0) ? 0.0 : (rawStart + paddingDuration)
                let safeEnd = rawEnd
                if (safeEnd - safeStart) >= 0.5 {
                    segments.append(TrimSegment(startTime: safeStart, endTime: safeEnd, type: .cursorInactivity))
                }
            }
        }
        
        return segments
    }
}
