import Foundation
import CoreGraphics

/// Viewport camera state representing current zoom scale, center offset, 3D tilt, and motion blur intensity
public struct ViewportState: Equatable, Sendable {
    public var focusPoint: CGPoint // Center of frame in normalized space (0.0 to 1.0)
    public var scale: CGFloat      // 1.0 = normal 100% (1X), 2.0 = 200%
    public var motionBlur: CGFloat // 0.0 (sharp) to 1.0 (peak motion blur during zoom in/out)
    public var pitch: Double
    public var yaw: Double
    public var roll: Double
    public var positionOffsetX: CGFloat
    public var positionOffsetY: CGFloat
    public var is3D: Bool
    
    public init(
        focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1.0,
        motionBlur: CGFloat = 0.0,
        pitch: Double = 0.0,
        yaw: Double = 0.0,
        roll: Double = 0.0,
        positionOffsetX: CGFloat = 0.0,
        positionOffsetY: CGFloat = 0.0,
        is3D: Bool = false
    ) {
        self.focusPoint = focusPoint
        self.scale = scale
        self.motionBlur = motionBlur
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.positionOffsetX = positionOffsetX
        self.positionOffsetY = positionOffsetY
        self.is3D = is3D
    }
    
    public static let fullScreen = ViewportState(
        focusPoint: CGPoint(x: 0.5, y: 0.5),
        scale: 1.0,
        motionBlur: 0.0,
        pitch: 0.0,
        yaw: 0.0,
        roll: 0.0,
        positionOffsetX: 0.0,
        positionOffsetY: 0.0,
        is3D: false
    )
}

/// Engine responsible for analyzing telemetry events and generating cinematic auto-zoom keyframes
public final class AutoZoomEngine: @unchecked Sendable {
    
    /// Parameters configuring how auto-zoom detects and frames action
    public struct Configuration: Sendable {
        public var clusterWindowDuration: TimeInterval = 2.5
        public var defaultZoomScale: CGFloat = 2.5
        public var textInputZoomScale: CGFloat = 2.75
        public var maxZoomScale: CGFloat = 3.5
        public var minZoomScale: CGFloat = 1.0
        public var returnToFullViewIdleDelay: TimeInterval = 3.5
        public var transitionDuration: TimeInterval = 0.65
        public var edgeMargin: CGFloat = 0.15 // Prevent focus point from getting clipped at display borders
        
        public init() {}
    }
    
    public let config: Configuration
    
    public init(config: Configuration = Configuration()) {
        self.config = config
    }
    
    /// Generate a list of non-destructive ZoomKeyframes from raw telemetry events
    public func generateKeyframes(from events: [TelemetryEvent], totalDuration: TimeInterval) -> [ZoomKeyframe] {
        guard !events.isEmpty else { return [] }
        
        // Filter for focal events: mouse clicks, drags, and typing
        let focalEvents = events.filter { event in
            switch event.type {
            case .mouseClick, .mouseDrag, .keyDown:
                return event.position != nil
            default:
                return false
            }
        }.sorted { $0.timestamp < $1.timestamp }
        
        guard !focalEvents.isEmpty else { return [] }
        
        var keyframes: [ZoomKeyframe] = []
        var i = 0
        
        while i < focalEvents.count {
            let currentEvent = focalEvents[i]
            let clusterStartTime = max(0, currentEvent.timestamp - 0.2)
            
            // Gather all events within the cluster window
            var clusterPositions: [CGPoint] = []
            var isTyping = false
            var clusterEndTime = currentEvent.timestamp
            
            var j = i
            while j < focalEvents.count && (focalEvents[j].timestamp - clusterEndTime) <= config.clusterWindowDuration {
                let ev = focalEvents[j]
                if let pos = ev.position {
                    clusterPositions.append(pos)
                }
                if ev.type == .keyDown {
                    isTyping = true
                }
                clusterEndTime = max(clusterEndTime, ev.timestamp)
                j += 1
            }
            
            // Advance outer loop index
            i = max(i + 1, j)
            
            guard !clusterPositions.isEmpty else { continue }
            
            // Calculate weighted center of mass for cluster positions
            let avgX = clusterPositions.reduce(0.0) { $0 + $1.x } / CGFloat(clusterPositions.count)
            let avgY = clusterPositions.reduce(0.0) { $0 + $1.y } / CGFloat(clusterPositions.count)
            
            // True normalized focus point matching exact cursor location
            let focusPoint = CGPoint(x: max(0.0, min(1.0, avgX)), y: max(0.0, min(1.0, avgY)))
            
            let scale = isTyping ? config.textInputZoomScale : config.defaultZoomScale
            let duration = max(1.8, (clusterEndTime - clusterStartTime) + 1.2)
            
            keyframes.append(
                ZoomKeyframe(
                    startTime: clusterStartTime,
                    duration: duration,
                    focusPoint: focusPoint,
                    scale: scale,
                    easing: .springSmooth,
                    isAutoGenerated: true,
                    reason: isTyping ? "text_input" : "click_cluster"
                )
            )
        }
        
        return keyframes
    }
    
    /// Retrieve smooth interpolated cursor position at a given playback timestamp from telemetry events
    public func cursorPosition(at time: TimeInterval, from events: [TelemetryEvent], fallback: CGPoint) -> CGPoint {
        guard !events.isEmpty else { return fallback }
        
        let validEvents = events.filter { $0.position != nil }.sorted { $0.timestamp < $1.timestamp }
        guard !validEvents.isEmpty else { return fallback }
        
        // Exact or before first event
        if time <= validEvents.first!.timestamp {
            return validEvents.first!.position ?? fallback
        }
        // Exact or after last event
        if time >= validEvents.last!.timestamp {
            return validEvents.last!.position ?? fallback
        }
        
        // Binary search for enclosing time pair
        var low = 0
        var high = validEvents.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let t = validEvents[mid].timestamp
            if t == time {
                return validEvents[mid].position ?? fallback
            } else if t < time {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        let prevIdx = max(0, high)
        let nextIdx = min(validEvents.count - 1, low)
        let e0 = validEvents[prevIdx]
        let e1 = validEvents[nextIdx]
        
        guard let p0 = e0.position, let p1 = e1.position else { return fallback }
        
        let dt = e1.timestamp - e0.timestamp
        if dt <= 0.001 { return p0 }
        
        let progress = (time - e0.timestamp) / dt
        let eased = cubicEaseInOut(progress)
        
        let x = p0.x + (p1.x - p0.x) * CGFloat(eased)
        let y = p0.y + (p1.y - p0.y) * CGFloat(eased)
        return CGPoint(x: x, y: y)
    }
    
    /// Smart Smooth Cinematic Focus with Deadzone & Smooth Inertia (FocuSee style)
    public func smoothCameraFocus(at time: TimeInterval, from events: [TelemetryEvent], basePoint: CGPoint) -> CGPoint {
        guard !events.isEmpty else { return basePoint }
        
        let target = cursorPosition(at: time, from: events, fallback: basePoint)
        
        // Deadzone test relative to base keyframe anchor:
        let distFromBase = hypot(target.x - basePoint.x, target.y - basePoint.y)
        if distFromBase < 0.035 { // ~3.5% deadzone radius: small micro-motions don't jerk the camera
            return basePoint
        }
        
        // Smooth window averaging around current time (0.35s window) for cinematic ease
        let windowStart = max(0, time - 0.25)
        let windowEnd = time + 0.15
        let nearbyEvents = events.filter {
            $0.position != nil && $0.timestamp >= windowStart && $0.timestamp <= windowEnd
        }
        
        guard !nearbyEvents.isEmpty else {
            return target
        }
        
        var totalWeight: CGFloat = 0.0
        var sumX: CGFloat = 0.0
        var sumY: CGFloat = 0.0
        
        for ev in nearbyEvents {
            guard let pos = ev.position else { continue }
            // Temporal weight centered around current playback time
            let dt = abs(ev.timestamp - time)
            let weight = CGFloat(exp(-dt * 6.0))
            sumX += pos.x * weight
            sumY += pos.y * weight
            totalWeight += weight
        }
        
        if totalWeight > 0.001 {
            let smoothX = sumX / totalWeight
            let smoothY = sumY / totalWeight
            return CGPoint(x: smoothX, y: smoothY)
        }
        
        return target
    }
    
    /// Calculate the interpolated viewport (scale, center, 3D tilt, and dynamic motion blur) at any playback timestamp
    public func evaluateViewport(
        at time: TimeInterval,
        with keyframes: [ZoomKeyframe],
        telemetry: [TelemetryEvent] = []
    ) -> ViewportState {
        guard !keyframes.isEmpty else { return .fullScreen }
        
        // Find keyframe active at this time or between transitions
        for keyframe in keyframes {
            let zoomInStart = keyframe.startTime
            let zoomInEnd = zoomInStart + config.transitionDuration
            let zoomOutStart = keyframe.startTime + keyframe.duration - config.transitionDuration
            let zoomOutEnd = keyframe.startTime + keyframe.duration
            
            if time < zoomInStart {
                continue
            }
            
            let is3D = keyframe.effectType == .motion3D
            
            // Determine active target focus point (smart cinematic cursor tracking with deadzone)
            let activeFocus = smoothCameraFocus(at: time, from: telemetry, basePoint: keyframe.focusPoint)
            
            // Zooming in phase with dynamic motion blur
            if time >= zoomInStart && time < zoomInEnd {
                let progress = (time - zoomInStart) / config.transitionDuration
                let eased = cubicEaseInOut(progress)
                
                let currentScale = 1.0 + (keyframe.scale - 1.0) * CGFloat(eased)
                let currentX = 0.5 + (activeFocus.x - 0.5) * CGFloat(eased)
                let currentY = 0.5 + (activeFocus.y - 0.5) * CGFloat(eased)
                
                // Calculate target angles using the dynamic focus point
                let currentFocus = CGPoint(x: currentX, y: currentY)
                let targetAngles = is3D ? keyframe.tiltPreset.angles(
                    focusPoint: currentFocus,
                    customPitch: keyframe.customPitch,
                    customYaw: keyframe.customYaw,
                    customRoll: keyframe.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                let currentPitch = targetAngles.pitch * eased
                let currentYaw = targetAngles.yaw * eased
                let currentRoll = targetAngles.roll * eased
                let curPosX = keyframe.positionOffsetX * CGFloat(eased)
                let curPosY = keyframe.positionOffsetY * CGFloat(eased)
                
                // Motion blur peaks at midpoint of the camera rush
                let blur = CGFloat(sin(.pi * progress)) * min(1.0, max(0.4, (keyframe.scale - 1.0) / 1.2))
                
                return ViewportState(
                    focusPoint: currentFocus,
                    scale: currentScale,
                    motionBlur: blur,
                    pitch: currentPitch,
                    yaw: currentYaw,
                    roll: currentRoll,
                    positionOffsetX: curPosX,
                    positionOffsetY: curPosY,
                    is3D: is3D
                )
            }
            
            // Holding zoomed state phase (follows cursor smoothly in real time!)
            if time >= zoomInEnd && time < zoomOutStart {
                let targetAngles = is3D ? keyframe.tiltPreset.angles(
                    focusPoint: activeFocus,
                    customPitch: keyframe.customPitch,
                    customYaw: keyframe.customYaw,
                    customRoll: keyframe.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                return ViewportState(
                    focusPoint: activeFocus,
                    scale: keyframe.scale,
                    motionBlur: 0.0,
                    pitch: targetAngles.pitch,
                    yaw: targetAngles.yaw,
                    roll: targetAngles.roll,
                    positionOffsetX: keyframe.positionOffsetX,
                    positionOffsetY: keyframe.positionOffsetY,
                    is3D: is3D
                )
            }
            
            // Zooming out phase with dynamic motion blur
            if time >= zoomOutStart && time <= zoomOutEnd {
                let progress = (time - zoomOutStart) / config.transitionDuration
                let eased = cubicEaseInOut(progress)
                
                let currentScale = keyframe.scale - (keyframe.scale - 1.0) * CGFloat(eased)
                let currentX = activeFocus.x - (activeFocus.x - 0.5) * CGFloat(eased)
                let currentY = activeFocus.y - (activeFocus.y - 0.5) * CGFloat(eased)
                
                // Calculate angles from interpolated focus point for auto mode
                let currentFocus = CGPoint(x: currentX, y: currentY)
                let fullAngles = is3D ? keyframe.tiltPreset.angles(
                    focusPoint: currentFocus,
                    customPitch: keyframe.customPitch,
                    customYaw: keyframe.customYaw,
                    customRoll: keyframe.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                let currentPitch = fullAngles.pitch * (1.0 - eased)
                let currentYaw = fullAngles.yaw * (1.0 - eased)
                let currentRoll = fullAngles.roll * (1.0 - eased)
                let curPosX = keyframe.positionOffsetX * CGFloat(1.0 - eased)
                let curPosY = keyframe.positionOffsetY * CGFloat(1.0 - eased)
                
                // Motion blur peaks while pulling back
                let blur = CGFloat(sin(.pi * progress)) * min(1.0, max(0.4, (keyframe.scale - 1.0) / 1.2))
                
                return ViewportState(
                    focusPoint: currentFocus,
                    scale: currentScale,
                    motionBlur: blur,
                    pitch: currentPitch,
                    yaw: currentYaw,
                    roll: currentRoll,
                    positionOffsetX: curPosX,
                    positionOffsetY: curPosY,
                    is3D: is3D
                )
            }
        }
        
        return .fullScreen
    }
    
    /// Smooth cubic bezier ease-in-out function
    private func cubicEaseInOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0.0), 1.0)
        return clamped < 0.5
            ? 4.0 * clamped * clamped * clamped
            : 1.0 - pow(-2.0 * clamped + 2.0, 3.0) / 2.0
    }
}
