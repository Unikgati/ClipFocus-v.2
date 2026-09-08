import Foundation

/// Represents a detected audio silence or filler interval recommended for automatic trimming
public struct TrimSegment: Codable, Identifiable, Sendable {
    public let id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var duration: TimeInterval { endTime - startTime }
    public var type: TrimType

    public enum TrimType: String, Codable, Sendable {
        case silence
        case fillerWord = "filler_word"
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
}
