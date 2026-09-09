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
        public var transitionDuration: TimeInterval = 0.95 // Slower, velvety smooth zoom in / out transitions
        public var edgeMargin: CGFloat = 0.15 // Prevent focus point from getting clipped at display borders
        
        public init() {}
    }
    
    public let config: Configuration
    
    public init(config: Configuration = Configuration()) {
        self.config = config
    }
    
    /// Generate a list of clean, non-overlapping, professional ZoomKeyframes from raw telemetry events
    public func generateKeyframes(from events: [TelemetryEvent], totalDuration: TimeInterval) -> [ZoomKeyframe] {
        guard !events.isEmpty else { return [] }
        
        // Filter for genuine user interactions during the recording.
        // Screen recorder standard: Filter out boundary start-clicks (first 0.55s) and stop-clicks (last 0.85s of recording),
        // preventing "ghost zoom blocks" caused by pressing Rec and Stop!
        let startDeadband: TimeInterval = 0.55
        let endDeadband: TimeInterval = max(0.5, totalDuration - 0.85)
        
        let focalEvents = events.filter { event in
            switch event.type {
            case .mouseClick, .mouseDrag, .keyDown:
                guard event.position != nil else { return false }
                if totalDuration >= 2.0 {
                    // Ignore start click (e.g. clicking REC or window focus)
                    if event.timestamp < startDeadband { return false }
                    // Ignore stop click (e.g. clicking Stop Recording button)
                    if event.timestamp > endDeadband && (event.type == .mouseClick || event.type == .mouseDrag) { return false }
                }
                return true
            default:
                return false
            }
        }.sorted { $0.timestamp < $1.timestamp }
        
        guard !focalEvents.isEmpty else { return [] }
        
        var rawClusters: [(startTime: TimeInterval, endTime: TimeInterval, focus: CGPoint, isTyping: Bool)] = []
        var i = 0
        
        while i < focalEvents.count {
            let currentEvent = focalEvents[i]
            let clusterStartTime = max(0, currentEvent.timestamp - 0.2)
            
            var clusterPositions: [CGPoint] = []
            var isTyping = false
            var clusterEndTime = currentEvent.timestamp
            
            var j = i
            // Continuous window coalescing (2.5s)
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
            
            i = max(i + 1, j)
            guard !clusterPositions.isEmpty else { continue }
            
            let avgX = clusterPositions.reduce(0.0) { $0 + $1.x } / CGFloat(clusterPositions.count)
            let avgY = clusterPositions.reduce(0.0) { $0 + $1.y } / CGFloat(clusterPositions.count)
            let focusPoint = CGPoint(x: max(0.0, min(1.0, avgX)), y: max(0.0, min(1.0, avgY)))
            
            rawClusters.append((
                startTime: clusterStartTime,
                endTime: clusterEndTime,
                focus: focusPoint,
                isTyping: isTyping
            ))
        }
        
        guard !rawClusters.isEmpty else { return [] }
        
        // Step 2: Intelligent Multi-Focal Spatial Clustering (FocuSee / Screen Studio pro logic)
        // Only merge events if they are in the same local screen area (< 0.22 distance).
        // If an interaction happens at a distinct location (> 0.22 distance), keep it as a distinct focal target!
        var mergedClusters: [(startTime: TimeInterval, endTime: TimeInterval, focus: CGPoint, isTyping: Bool)] = []
        
        for cluster in rawClusters {
            if let last = mergedClusters.last {
                let timeGap = cluster.startTime - last.endTime
                let dist = hypot(cluster.focus.x - last.focus.x, cluster.focus.y - last.focus.y)
                
                // If in the same local area (< 0.22 distance) and close in time (< 3.0s), merge into one cluster
                if dist <= 0.22 && timeGap <= 3.0 {
                    var updated = last
                    updated.endTime = max(last.endTime, cluster.endTime)
                    updated.focus = CGPoint(
                        x: (last.focus.x * 0.5) + (cluster.focus.x * 0.5),
                        y: (last.focus.y * 0.5) + (cluster.focus.y * 0.5)
                    )
                    updated.isTyping = last.isTyping || cluster.isTyping
                    mergedClusters[mergedClusters.count - 1] = updated
                    continue
                }
            }
            mergedClusters.append(cluster)
        }
        
        // Step 3: Build seamless, contiguous keyframes (Abutting with 0-gap for seamless morphing)
        var keyframes: [ZoomKeyframe] = []
        
        for (idx, cluster) in mergedClusters.enumerated() {
            let scale = cluster.isTyping ? config.textInputZoomScale : config.defaultZoomScale
            let idealDuration = max(3.0, (cluster.endTime - cluster.startTime) + 2.0)
            
            var start = cluster.startTime
            var dur = idealDuration
            
            // If previous keyframe exists:
            if let prev = keyframes.last {
                let prevEnd = prev.startTime + prev.duration
                // If cluster starts within 2.5s of prevEnd, snap contiguously (zero gap) to enable seamless gliding morph!
                if start <= prevEnd + 2.5 {
                    start = prevEnd
                }
            }
            
            // If next cluster exists and is close:
            if idx + 1 < mergedClusters.count {
                let nextStart = mergedClusters[idx + 1].startTime
                if (start + dur) > nextStart {
                    dur = max(1.8, nextStart - start)
                }
            }
            
            // Clamp within total video duration
            if (start + dur) > totalDuration {
                dur = max(1.2, totalDuration - start)
            }
            
            if start < totalDuration && dur >= 1.0 {
                keyframes.append(
                    ZoomKeyframe(
                        startTime: start,
                        duration: dur,
                        focusPoint: cluster.focus,
                        scale: scale,
                        easing: .springSmooth,
                        effectType: .zoom2D,
                        tiltPreset: .flat,
                        isAutoGenerated: true,
                        reason: cluster.isTyping ? "text_input" : "click_cluster"
                    )
                )
            }
        }
        
        return keyframes
    }
    
    /// Retrieve smooth interpolated cursor position at a given playback timestamp from telemetry events
    public func cursorPosition(at time: TimeInterval, from events: [TelemetryEvent], fallback: CGPoint) -> CGPoint {
        guard !events.isEmpty else { return fallback }
        
        // Exact or before first event
        if time <= events.first!.timestamp {
            return events.first!.position ?? fallback
        }
        // Exact or after last event
        if time >= events.last!.timestamp {
            return events.last!.position ?? fallback
        }
        
        // Binary search for enclosing time pair
        var low = 0
        var high = events.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let t = events[mid].timestamp
            if t == time {
                return events[mid].position ?? fallback
            } else if t < time {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        let prevIdx = max(0, high)
        let nextIdx = min(events.count - 1, low)
        let e0 = events[prevIdx]
        let e1 = events[nextIdx]
        
        guard let p0 = e0.position, let p1 = e1.position else { return fallback }
        
        let dt = e1.timestamp - e0.timestamp
        if dt <= 0.001 { return p0 }
        
        let progress = (time - e0.timestamp) / dt
        // Smoothstep (3t^2 - 2t^3) removes sharp C0 velocity kinks between discrete telemetry samples
        let smoothP = progress * progress * (3.0 - 2.0 * progress)
        let x = p0.x + (p1.x - p0.x) * CGFloat(smoothP)
        let y = p0.y + (p1.y - p0.y) * CGFloat(smoothP)
        return CGPoint(x: x, y: y)
    }
    
    /// Professional Viewport Push-Box Framing (FocuSee / Screen Studio style)
    /// 
    /// 1. Expansive Deadzone Safe Zone (~82% of visible zoomed viewport): Camera is 100% stationary and locked on a virtual tripod.
    /// 2. C^2 Smooth Rim Cushioning (Zero Derivative at Boundary): Eliminates all micro-jitter or vibration when shaking the cursor near the safe zone edge.
    /// 3. Progressive Edge Push: Smoothly and gradually adjusts framing when cursor pushes well outside the safe zone.
    public func smoothCameraFocus(at time: TimeInterval, from events: [TelemetryEvent], basePoint: CGPoint, scale: CGFloat = 2.0) -> CGPoint {
        guard !events.isEmpty else { return basePoint }
        
        let effScale = max(1.0, scale)
        
        // Half-span of visible screen viewport at this zoom scale:
        let halfSpanX = (0.5 / effScale)
        let halfSpanY = (0.5 / effScale)
        
        // Expansive Safe Deadzone (82% of visible viewport from camera anchor)
        // Inside this large zone, camera is completely LOCKED on tripod (0.000 movement)
        let deadzoneRadiusX = halfSpanX * 0.82
        let deadzoneRadiusY = halfSpanY * 0.82
        let cushionSpanX = max(0.001, halfSpanX * 0.18)
        let cushionSpanY = max(0.001, halfSpanY * 0.18)
        
        // Compute Push-Box camera target with C^2 continuous rim cushioning
        let computePushBoxTarget: (CGPoint) -> CGPoint = { pos in
            let dx = pos.x - basePoint.x
            let dy = pos.y - basePoint.y
            let absDx = abs(dx)
            let absDy = abs(dy)
            
            var shiftX: CGFloat = 0.0
            var shiftY: CGFloat = 0.0
            
            // X-Axis C^2 Smooth Cushioning: zero slope at boundary = zero boundary jitter!
            if absDx > deadzoneRadiusX {
                let excess = absDx - deadzoneRadiusX
                let ratio = min(1.0, excess / cushionSpanX)
                // Smoothstep (3r^2 - 2r^3): continuous 1st and 2nd derivatives
                let easedRatio = CGFloat(ratio * ratio * (3.0 - 2.0 * Double(ratio)))
                shiftX = (dx > 0 ? 1.0 : -1.0) * (excess * (0.35 + 0.65 * easedRatio))
            }
            
            // Y-Axis C^2 Smooth Cushioning: zero slope at boundary = zero boundary jitter!
            if absDy > deadzoneRadiusY {
                let excess = absDy - deadzoneRadiusY
                let ratio = min(1.0, excess / cushionSpanY)
                let easedRatio = CGFloat(ratio * ratio * (3.0 - 2.0 * Double(ratio)))
                shiftY = (dy > 0 ? 1.0 : -1.0) * (excess * (0.35 + 0.65 * easedRatio))
            }
            
            let camX = basePoint.x + shiftX
            let camY = basePoint.y + shiftY
            
            // Safe display margins clamp
            let clampedX = max(halfSpanX, min(1.0 - halfSpanX, camX))
            let clampedY = max(halfSpanY, min(1.0 - halfSpanY, camY))
            return CGPoint(x: clampedX, y: clampedY)
        }
        
        // Continuous Smooth Gaussian Integration (0.80s window, 21 samples, sigma = 0.30s)
        let sampleCount = 21
        let dtStep = 0.04
        let halfSpanSamples = Double(sampleCount - 1) / 2.0
        let sigma = 0.30
        
        var totalWeight: CGFloat = 0.0
        var sumX: CGFloat = 0.0
        var sumY: CGFloat = 0.0
        
        for i in 0..<sampleCount {
            let offsetSec = (Double(i) - halfSpanSamples) * dtStep
            let sampleTime = max(0, time + offsetSec)
            let samplePos = cursorPosition(at: sampleTime, from: events, fallback: basePoint)
            let pushTarget = computePushBoxTarget(samplePos)
            
            let weight = CGFloat(exp(-0.5 * pow(offsetSec / sigma, 2.0)))
            sumX += pushTarget.x * weight
            sumY += pushTarget.y * weight
            totalWeight += weight
        }
        
        if totalWeight > 0.001 {
            let resX = sumX / totalWeight
            let resY = sumY / totalWeight
            return CGPoint(x: max(halfSpanX, min(1.0 - halfSpanX, resX)), y: max(halfSpanY, min(1.0 - halfSpanY, resY)))
        }
        
        let curPos = cursorPosition(at: time, from: events, fallback: basePoint)
        return computePushBoxTarget(curPos)
    }
    
    /// Calculate the interpolated viewport (scale, center, 3D tilt, and dynamic motion blur) at any playback timestamp
    /// Supports seamless direct camera morphing between adjacent/abutting keyframes (FocuSee / Screen Studio style)
    public func evaluateViewport(
        at time: TimeInterval,
        with keyframes: [ZoomKeyframe],
        telemetry: [TelemetryEvent] = []
    ) -> ViewportState {
        guard !keyframes.isEmpty else { return .fullScreen }
        
        // Pre-filter valid events once per evaluation
        let validEvents = telemetry.filter { $0.position != nil }
        let sortedKFs = keyframes.sorted { $0.startTime < $1.startTime }
        
        let adjacencyThreshold: TimeInterval = 0.85
        
        for i in 0..<sortedKFs.count {
            let kf = sortedKFs[i]
            let hasPrevAdjacent = (i > 0 && abs(kf.startTime - (sortedKFs[i-1].startTime + sortedKFs[i-1].duration)) <= adjacencyThreshold)
            let hasNextAdjacent = (i < sortedKFs.count - 1 && abs(sortedKFs[i+1].startTime - (kf.startTime + kf.duration)) <= adjacencyThreshold)
            let nextKF = hasNextAdjacent ? sortedKFs[i+1] : nil
            let prevKF = hasPrevAdjacent ? sortedKFs[i-1] : nil
            
            let is3D = kf.effectType == .motion3D
            
            // 1. Inbound transition calculations
            let transIn = min(config.transitionDuration, kf.duration * 0.45)
            let zoomInStart = kf.startTime
            let zoomInEnd = zoomInStart + transIn
            
            // 2. Outbound / Morph transition calculations
            let morphStart: TimeInterval
            let morphEnd: TimeInterval
            let transOut = min(config.transitionDuration, kf.duration * 0.45)
            let zoomOutStart = kf.startTime + kf.duration - transOut
            let zoomOutEnd = kf.startTime + kf.duration
            
            if let next = nextKF {
                let boundary = (kf.startTime + kf.duration + next.startTime) / 2.0
                let dist = hypot(next.focusPoint.x - kf.focusPoint.x, next.focusPoint.y - kf.focusPoint.y)
                
                // Adaptive duration based on distance (longer for corner-to-corner sweeps)
                let baseDur = config.transitionDuration + Double(min(1.0, dist)) * 0.35
                let morphDur = min(baseDur, kf.duration * 0.50, next.duration * 0.50)
                
                // Cinematic Anticipation Hold:
                // Shift the morph window slightly forward so the first corner holds ~0.35s longer
                // allowing the viewer to absorb the interaction before the camera sweeps across.
                let leadInRatio = dist > 0.25 ? 0.30 : 0.50
                morphStart = boundary - (morphDur * leadInRatio)
                morphEnd = boundary + (morphDur * (1.0 - leadInRatio))
            } else {
                morphStart = zoomOutStart
                morphEnd = zoomOutEnd
            }
            
            // 3. Hold window boundaries
            let holdStart: TimeInterval
            if let prev = prevKF {
                let boundaryPrev = (prev.startTime + prev.duration + kf.startTime) / 2.0
                let distPrev = hypot(kf.focusPoint.x - prev.focusPoint.x, kf.focusPoint.y - prev.focusPoint.y)
                let baseDurPrev = config.transitionDuration + Double(min(1.0, distPrev)) * 0.35
                let morphDurPrev = min(baseDurPrev, prev.duration * 0.50, kf.duration * 0.50)
                let leadInRatioPrev = distPrev > 0.25 ? 0.30 : 0.50
                holdStart = boundaryPrev + (morphDurPrev * (1.0 - leadInRatioPrev))
            } else {
                holdStart = zoomInEnd
            }
            
            let holdEnd: TimeInterval
            if nextKF != nil {
                holdEnd = morphStart
            } else {
                holdEnd = zoomOutStart
            }
            
            // Skip if timestamp is before this keyframe's active range
            let activeStart = hasPrevAdjacent ? holdStart : zoomInStart
            if time < activeStart {
                continue
            }
            
            // Case 1: Zoom In from Full Screen (Only if this is the start of a sequence)
            if !hasPrevAdjacent && time >= zoomInStart && time < zoomInEnd {
                let progress = (time - zoomInStart) / max(0.001, transIn)
                let eased = easyEaseInOut(progress)
                
                let currentScale = 1.0 + (kf.scale - 1.0) * CGFloat(eased)
                // Target destination anchor at zoom landing point (fixed anchor eliminates jitter/wobble during zoom-in transition)
                let targetFocus = smoothCameraFocus(at: zoomInEnd, from: validEvents, basePoint: kf.focusPoint, scale: kf.scale)
                let currentX = 0.5 + (targetFocus.x - 0.5) * CGFloat(eased)
                let currentY = 0.5 + (targetFocus.y - 0.5) * CGFloat(eased)
                let currentFocus = CGPoint(x: currentX, y: currentY)
                
                let destAngles = is3D ? kf.tiltPreset.angles(
                    focusPoint: targetFocus,
                    customPitch: kf.customPitch,
                    customYaw: kf.customYaw,
                    customRoll: kf.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                let currentPitch = destAngles.pitch * eased
                let currentYaw = destAngles.yaw * eased
                let currentRoll = destAngles.roll * eased
                let curPosX = kf.positionOffsetX * CGFloat(eased)
                let curPosY = kf.positionOffsetY * CGFloat(eased)
                
                let blur = CGFloat(sin(.pi * progress)) * min(1.0, max(0.4, (kf.scale - 1.0) / 1.2))
                
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
            
            // Case 2: Holding zoomed state (Steadicam cursor radar tracking)
            if time >= holdStart && time < holdEnd {
                let activeFocus = smoothCameraFocus(at: time, from: validEvents, basePoint: kf.focusPoint, scale: kf.scale)
                let targetAngles = is3D ? kf.tiltPreset.angles(
                    focusPoint: activeFocus,
                    customPitch: kf.customPitch,
                    customYaw: kf.customYaw,
                    customRoll: kf.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                return ViewportState(
                    focusPoint: activeFocus,
                    scale: kf.scale,
                    motionBlur: 0.0,
                    pitch: targetAngles.pitch,
                    yaw: targetAngles.yaw,
                    roll: targetAngles.roll,
                    positionOffsetX: kf.positionOffsetX,
                    positionOffsetY: kf.positionOffsetY,
                    is3D: is3D
                )
            }
            
            // Case 3A: Seamless Camera Morph into Adjacent Successor (Zero dip to 1.0x!)
            if let next = nextKF, time >= morphStart && time <= morphEnd {
                let progress = (time - morphStart) / max(0.001, morphEnd - morphStart)
                let eased = easyEaseInOut(progress)
                
                let startFocus = smoothCameraFocus(at: morphStart, from: validEvents, basePoint: kf.focusPoint, scale: kf.scale)
                let endFocus = smoothCameraFocus(at: morphEnd, from: validEvents, basePoint: next.focusPoint, scale: next.scale)
                
                let currentScale = kf.scale + (next.scale - kf.scale) * CGFloat(eased)
                let currentFocus = CGPoint(
                    x: startFocus.x + (endFocus.x - startFocus.x) * CGFloat(eased),
                    y: startFocus.y + (endFocus.y - startFocus.y) * CGFloat(eased)
                )
                
                let is3D_prev = kf.effectType == .motion3D
                let is3D_next = next.effectType == .motion3D
                let startAngles = is3D_prev ? kf.tiltPreset.angles(
                    focusPoint: startFocus,
                    customPitch: kf.customPitch,
                    customYaw: kf.customYaw,
                    customRoll: kf.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                let endAngles = is3D_next ? next.tiltPreset.angles(
                    focusPoint: endFocus,
                    customPitch: next.customPitch,
                    customYaw: next.customYaw,
                    customRoll: next.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                let currentPitch = startAngles.pitch + (endAngles.pitch - startAngles.pitch) * eased
                let currentYaw = startAngles.yaw + (endAngles.yaw - startAngles.yaw) * eased
                let currentRoll = startAngles.roll + (endAngles.roll - startAngles.roll) * eased
                let curPosX = kf.positionOffsetX + (next.positionOffsetX - kf.positionOffsetX) * CGFloat(eased)
                let curPosY = kf.positionOffsetY + (next.positionOffsetY - kf.positionOffsetY) * CGFloat(eased)
                
                let blur = CGFloat(sin(.pi * progress)) * min(1.0, max(0.4, (max(kf.scale, next.scale) - 1.0) / 1.2))
                
                return ViewportState(
                    focusPoint: currentFocus,
                    scale: currentScale,
                    motionBlur: blur,
                    pitch: currentPitch,
                    yaw: currentYaw,
                    roll: currentRoll,
                    positionOffsetX: curPosX,
                    positionOffsetY: curPosY,
                    is3D: is3D_prev || is3D_next
                )
            }
            
            // Case 3B: Zoom Out to Full Screen (Only at the end of a sequence)
            if !hasNextAdjacent && time >= zoomOutStart && time <= zoomOutEnd {
                let progress = (time - zoomOutStart) / max(0.001, transOut)
                let eased = easyEaseInOut(progress)
                let currentScale = kf.scale - (kf.scale - 1.0) * CGFloat(eased)
                // Origin anchor at start of zoom-out (fixed anchor eliminates wobble during departure)
                let startFocus = smoothCameraFocus(at: zoomOutStart, from: validEvents, basePoint: kf.focusPoint, scale: kf.scale)
                
                let currentX = startFocus.x - (startFocus.x - 0.5) * CGFloat(eased)
                let currentY = startFocus.y - (startFocus.y - 0.5) * CGFloat(eased)
                let currentFocus = CGPoint(x: currentX, y: currentY)
                
                let startAngles = is3D ? kf.tiltPreset.angles(
                    focusPoint: startFocus,
                    customPitch: kf.customPitch,
                    customYaw: kf.customYaw,
                    customRoll: kf.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                let currentPitch = startAngles.pitch * (1.0 - eased)
                let currentYaw = startAngles.yaw * (1.0 - eased)
                let currentRoll = startAngles.roll * (1.0 - eased)
                let curPosX = kf.positionOffsetX * CGFloat(1.0 - eased)
                let curPosY = kf.positionOffsetY * CGFloat(1.0 - eased)
                
                let blur = CGFloat(sin(.pi * progress)) * min(1.0, max(0.4, (kf.scale - 1.0) / 1.2))
                
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
    
    /// Cinematic Quintic Easy-Ease function (matching After Effects / FocuSee camera moves)
    /// Smooth velocity at start (0 acceleration jerk), energetic glide, and velvet-smooth asymptotic landing.
    private func easyEaseInOut(_ t: Double) -> Double {
        let x = min(max(t, 0.0), 1.0)
        // Quintic smoothstep: 6x^5 - 15x^4 + 10x^3
        return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
    }
}
