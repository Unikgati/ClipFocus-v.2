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
    public func generateKeyframes(
        from events: [TelemetryEvent],
        totalDuration: TimeInterval,
        preferredEffectType: ZoomEffectType = .zoom2D,
        autoZoomOnTyping: Bool = true
    ) -> [ZoomKeyframe] {
        guard !events.isEmpty else { return [] }
        
        // Filter for genuine user interactions during the recording.
        // Screen recorder standard: Filter out boundary start-clicks (first 0.55s) and stop-clicks (last 0.85s of recording),
        // preventing "ghost zoom blocks" caused by pressing Rec and Stop!
        let startDeadband: TimeInterval = 0.55
        let endDeadband: TimeInterval = max(0.5, totalDuration - 0.85)
        
        let focalEvents = events.filter { event in
            switch event.type {
            case .mouseClick, .mouseDrag:
                guard event.position != nil else { return false }
                if totalDuration >= 2.0 {
                    // Ignore start click (e.g. clicking REC or window focus)
                    if event.timestamp < startDeadband { return false }
                    // Ignore stop click (e.g. clicking Stop Recording button)
                    if event.timestamp > endDeadband && (event.type == .mouseClick || event.type == .mouseDrag) { return false }
                }
                return true
            case .keyDown:
                guard autoZoomOnTyping, event.position != nil else { return false }
                if totalDuration >= 2.0 {
                    if event.timestamp < startDeadband { return false }
                    if event.timestamp > endDeadband { return false }
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
            let firstPos = currentEvent.position ?? CGPoint(x: 0.5, y: 0.5)
            
            var j = i
            // Continuous window coalescing: only group events that are spatially in the same region (< 0.28 distance)
            while j < focalEvents.count && (focalEvents[j].timestamp - clusterEndTime) <= config.clusterWindowDuration {
                let ev = focalEvents[j]
                if let pos = ev.position {
                    let dist = hypot(pos.x - firstPos.x, pos.y - firstPos.y)
                    // If user clicks at a distinct separate location (> 0.28 distance), start a new focal keyframe!
                    if dist > 0.28 && ev.type == .mouseClick {
                        break
                    }
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
            let idealDuration = max(2.5, (cluster.endTime - cluster.startTime) + 2.0)
            
            var start = cluster.startTime
            var dur = idealDuration
            
            // If previous keyframe exists:
            if let prev = keyframes.last {
                let prevEnd = prev.startTime + prev.duration
                if start < prevEnd {
                    // New cluster begins before previous finished its full ideal duration:
                    // trim previous keyframe duration to start of new cluster so camera morphs on time!
                    let trimmedDur = max(1.2, cluster.startTime - prev.startTime)
                    keyframes[keyframes.count - 1].duration = trimmedDur
                    start = prev.startTime + trimmedDur
                } else if start <= prevEnd + 2.0 {
                    start = prevEnd
                }
            }
            
            // If next cluster exists and is close:
            if idx + 1 < mergedClusters.count {
                let nextStart = mergedClusters[idx + 1].startTime
                if (start + dur) > nextStart {
                    dur = max(1.2, nextStart - start)
                }
            }
            
            // Clamp within total video duration
            if (start + dur) > totalDuration {
                dur = max(1.0, totalDuration - start)
            }
            
            if start < totalDuration && dur >= 0.8 {
                let effect = preferredEffectType
                let tilt: TiltPreset = (effect == .motion3D) ? .auto : .flat
                keyframes.append(
                    ZoomKeyframe(
                        startTime: start,
                        duration: dur,
                        focusPoint: cluster.focus,
                        scale: scale,
                        easing: .springSmooth,
                        effectType: effect,
                        tiltPreset: tilt,
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
        
        // For long telemetry pauses (> 0.20s), the mouse was stationary at p0
        // and only began moving in the window immediately before e1.
        // For active movement (dt <= 0.20s), interpolate smoothly across the entire dt.
        let motionDur = min(dt, 0.20)
        let motionStart = e1.timestamp - motionDur
        if time <= motionStart {
            return p0
        }
        
        let progress = max(0.0, min(1.0, (time - motionStart) / motionDur))
        // Smoothstep (3t^2 - 2t^3) removes sharp C0 velocity kinks between discrete telemetry samples
        let smoothP = progress * progress * (3.0 - 2.0 * progress)
        let x = p0.x + (p1.x - p0.x) * CGFloat(smoothP)
        let y = p0.y + (p1.y - p0.y) * CGFloat(smoothP)
        return CGPoint(x: x, y: y)
    }
    
    /// Check whether any meaningful interaction (click, drag, key typing) occurred in temporal and spatial proximity
    private func hasInteraction(near position: CGPoint, at time: TimeInterval, in events: [TelemetryEvent]) -> Bool {
        let window: TimeInterval = 0.35
        let radius: CGFloat = 0.25
        let minTime = time - window
        let maxTime = time + window
        
        if events.count <= 16 {
            return events.contains { ev in
                guard ev.timestamp >= minTime && ev.timestamp <= maxTime else { return false }
                switch ev.type {
                case .mouseClick, .mouseDrag, .keyDown:
                    if let p = ev.position {
                        return hypot(p.x - position.x, p.y - position.y) <= radius
                    }
                    return true
                default:
                    return false
                }
            }
        }
        
        var low = 0
        var high = events.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if events[mid].timestamp < minTime {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        var idx = max(0, high)
        while idx < events.count && events[idx].timestamp <= maxTime {
            let ev = events[idx]
            if ev.timestamp >= minTime {
                switch ev.type {
                case .mouseClick, .mouseDrag, .keyDown:
                    if let p = ev.position {
                        if hypot(p.x - position.x, p.y - position.y) <= radius {
                            return true
                        }
                    } else {
                        return true
                    }
                default:
                    break
                }
            }
            idx += 1
        }
        return false
    }
    
    /// Retrieve stabilized cursor position suppressing insignificant transient movements (flicks/reversals/waypoint detours with no interaction)
    public func stabilizedCursorPosition(at time: TimeInterval, from events: [TelemetryEvent], fallback: CGPoint) -> CGPoint {
        guard !events.isEmpty else { return fallback }
        
        let curPos = cursorPosition(at: time, from: events, fallback: fallback)
        
        // Preserve important interactions (click, drag, typing) within proximity
        if hasInteraction(near: curPos, at: time, in: events) {
            return curPos
        }
        
        // Continuous projection-based analysis over horizon tau = 0.30s
        let tau: Double = 0.30
        let tPast = max(0.0, time - tau)
        let tFuture = time + tau
        let pPast = cursorPosition(at: tPast, from: events, fallback: fallback)
        let pFuture = cursorPosition(at: tFuture, from: events, fallback: fallback)
        
        // Segment projection: find closest point on segment [pPast, pFuture]
        let vx = pFuture.x - pPast.x
        let vy = pFuture.y - pPast.y
        let lenSq = vx * vx + vy * vy
        
        let projX: CGFloat
        let projY: CGFloat
        if lenSq < 0.0001 {
            projX = pPast.x
            projY = pPast.y
        } else {
            let wx = curPos.x - pPast.x
            let wy = curPos.y - pPast.y
            let param = max(0.0, min(1.0, (wx * vx + wy * vy) / lenSq))
            projX = pPast.x + param * vx
            projY = pPast.y + param * vy
        }
        
        let excX = curPos.x - projX
        let excY = curPos.y - projY
        let excDist = hypot(excX, excY)
        guard excDist > 0.02 else { return curPos }
        
        // Prevent directional fighting: if pulling towards projection would pull backwards
        // against the cursor's forward movement towards its future destination, do not fight!
        let toFutX = pFuture.x - curPos.x
        let toFutY = pFuture.y - curPos.y
        let toBaseX = projX - curPos.x
        let toBaseY = projY - curPos.y
        let alignment = toBaseX * toFutX + toBaseY * toFutY
        guard alignment > 0.0 else { return curPos }
        
        let futDist = hypot(toFutX, toFutY)
        let denom = max(0.0001, excDist * futDist)
        let alignRatio = max(0.0, min(1.0, Double(alignment / denom)))
        let alignAlpha = alignRatio * alignRatio * (3.0 - 2.0 * alignRatio)
        
        // Smooth C^2 continuous transition factors with zero step-discontinuities
        let dPast = hypot(curPos.x - pPast.x, curPos.y - pPast.y)
        let dFuture = hypot(curPos.x - pFuture.x, curPos.y - pFuture.y)
        let minTravel = min(dPast, dFuture)
        
        let excNorm = Double(max(0.0, min(1.0, (excDist - 0.02) / 0.08)))
        let excAlpha = excNorm * excNorm * (3.0 - 2.0 * excNorm)
        
        let travelNorm = Double(max(0.0, min(1.0, (minTravel - 0.02) / 0.06)))
        let travelAlpha = travelNorm * travelNorm * (3.0 - 2.0 * travelNorm)
        
        let alpha = CGFloat(excAlpha * travelAlpha * alignAlpha)
        guard alpha > 0.001 else { return curPos }
        
        return CGPoint(
            x: curPos.x + toBaseX * alpha,
            y: curPos.y + toBaseY * alpha
        )
    }
    
    /// Professional Viewport Camera Steadicam Framing (Screen Studio / FocuSee style)
    /// 
    /// 1. Inner Tripod Deadzone (~28% of viewport): Camera is 100% stationary and locked on small hand twitches.
    /// 2. C^2 Smooth Acceleration: When moving between distant clicks (e.g. top to bottom), camera fluidly glides along.
    /// 3. Guaranteed Cursor Capture: Keeps cursor comfortably framed in the safe viewing area (center 60%), never clipped.
    public func smoothCameraFocus(at time: TimeInterval, from events: [TelemetryEvent], basePoint: CGPoint, scale: CGFloat = 2.0) -> CGPoint {
        guard !events.isEmpty else { return basePoint }
        
        let effScale = max(1.0, scale)
        let halfSpanX = (0.5 / effScale)
        let halfSpanY = (0.5 / effScale)
        
        // Inner tripod deadzone: small hand micro-shakes produce zero camera movement
        let innerDeadzoneX = halfSpanX * 0.28
        let innerDeadzoneY = halfSpanY * 0.28
        

        
        // Smooth C^2 boundary limiting ensuring camera target smoothly decelerates before reaching physical viewport limits
        let smoothStageBound: (CGFloat, CGFloat, CGFloat) -> CGFloat = { val, minVal, maxVal in
            if maxVal <= minVal { return (minVal + maxVal) * 0.5 }
            let margin: CGFloat = min(0.04, (maxVal - minVal) * 0.20)
            if val > maxVal - margin {
                let excess = val - (maxVal - margin)
                let span = margin * 2.0
                let t = min(1.0, max(0.0, excess / span))
                let eased = t * (2.0 - t)
                return min(maxVal, (maxVal - margin) + margin * eased)
            } else if val < minVal + margin {
                let deficit = (minVal + margin) - val
                let span = margin * 2.0
                let t = min(1.0, max(0.0, deficit / span))
                let eased = t * (2.0 - t)
                return max(minVal, (minVal + margin) - margin * eased)
            }
            return val
        }
        
        let computePushTarget: (CGPoint) -> CGPoint = { pos in
            let dx = pos.x - basePoint.x
            let dy = pos.y - basePoint.y
            
            // Unified 2D Elliptic Safe-Zone:
            // Eliminates decoupled-axis deadzone braking where secondary axis movement was frozen
            // while primary axis settled, causing the camera to hit an invisible brake during multi-axis catch-up.
            let normInX = dx / innerDeadzoneX
            let normInY = dy / innerDeadzoneY
            let rIn = hypot(normInX, normInY)
            
            let shiftX: CGFloat
            let shiftY: CGFloat
            
            if rIn <= 1.0 {
                // Inside inner safe zone: 100% stationary tripod lock
                shiftX = 0.0
                shiftY = 0.0
            } else {
                let ratioR: CGFloat = 0.65 / 0.28 // outerSpan / innerDeadzone
                let spanR = ratioR - 1.0
                let t = (rIn - 1.0) / spanR
                let radialShift: CGFloat
                if t >= 1.0 {
                    // Beyond outer safe boundary: strictly seamless 1:1 follow (derivative = 1.0, second derivative = 0.0)
                    radialShift = spanR * (t - 0.5)
                } else {
                    // Monotonic C^2 Quintic Smoothstep Integral:
                    // s'(t) = 6t^5 - 15t^4 + 10t^3 (strictly monotonic from 0.0 to 1.0, zero overshoot!)
                    // s''(t) = 30t^2 * (1 - t)^2 >= 0 everywhere on [0, 1]!
                    // Guarantees strictly non-negative acceleration during outward cursor tracking:
                    // 1. Zero initial velocity & zero acceleration jerk at inner deadzone (t=0): s(0)=0, s'(0)=0, s''(0)=0
                    // 2. Continuous, unbroken acceleration profile (t=0..1): s'(t) glides smoothly 0.0 -> 1.0 without surging to 1.51x and braking
                    // 3. Perfect C^2 smooth arrival at 1:1 linear follow (t=1): s(1)=0.5, s'(1)=1.0, s''(1)=0.0 with zero derivative jump or hitch
                    let s = t * t * t * t * (t * t - 3.0 * t + 2.5)
                    radialShift = spanR * s
                }
                let followFactor = radialShift / rIn
                shiftX = dx * followFactor
                shiftY = dy * followFactor
            }
            
            let targetX = smoothStageBound(basePoint.x + shiftX, halfSpanX, 1.0 - halfSpanX)
            let targetY = smoothStageBound(basePoint.y + shiftY, halfSpanY, 1.0 - halfSpanY)
            return CGPoint(x: targetX, y: targetY)
        }
        
        // Ultra-Smooth Cinematic Steadicam Inertia Kernel (~288ms effective delay, ~0.72s past horizon)
        // High-Precision 100Hz Grid (dt = 0.01s) with C^2 smooth polynomial onset and cubic ease-out deceleration
        // Eliminates 50Hz discrete tap-aliasing ripple, jitter, and stutter on 60Hz/120Hz ProMotion displays
        // w(u) = u^2 * (1 - u)^3 guarantees:
        // 1. Zero initial velocity & zero initial acceleration (h(0) = 0, h'(0) = 0): gradual, non-instant reaction
        // 2. Continuous momentum & gradual direction transition without sudden jerks or zigzags
        // 3. Velvety cubic ease-out landing (h(-T) = 0, h'(-T) = 0): gradual deceleration to rest with zero abrupt stop
        let sampleOffsets: [(dt: Double, weight: Double)] = [
            (-0.00, 0.000000),
            (-0.01, 0.000154),
            (-0.02, 0.000591),
            (-0.03, 0.001273),
            (-0.04, 0.002167),
            (-0.05, 0.003238),
            (-0.06, 0.004457),
            (-0.07, 0.005796),
            (-0.08, 0.007226),
            (-0.09, 0.008723),
            (-0.10, 0.010264),
            (-0.11, 0.011829),
            (-0.12, 0.013396),
            (-0.13, 0.014949),
            (-0.14, 0.016470),
            (-0.15, 0.017946),
            (-0.16, 0.019362),
            (-0.17, 0.020708),
            (-0.18, 0.021973),
            (-0.19, 0.023147),
            (-0.20, 0.024223),
            (-0.21, 0.025194),
            (-0.22, 0.026056),
            (-0.23, 0.026804),
            (-0.24, 0.027435),
            (-0.25, 0.027947),
            (-0.26, 0.028338),
            (-0.27, 0.028610),
            (-0.28, 0.028763),
            (-0.29, 0.028798),
            (-0.30, 0.028718),
            (-0.31, 0.028525),
            (-0.32, 0.028225),
            (-0.33, 0.027821),
            (-0.34, 0.027319),
            (-0.35, 0.026724),
            (-0.36, 0.026042),
            (-0.37, 0.025279),
            (-0.38, 0.024443),
            (-0.39, 0.023541),
            (-0.40, 0.022580),
            (-0.41, 0.021568),
            (-0.42, 0.020513),
            (-0.43, 0.019422),
            (-0.44, 0.018304),
            (-0.45, 0.017166),
            (-0.46, 0.016017),
            (-0.47, 0.014865),
            (-0.48, 0.013717),
            (-0.49, 0.012581),
            (-0.50, 0.011465),
            (-0.51, 0.010374),
            (-0.52, 0.009317),
            (-0.53, 0.008298),
            (-0.54, 0.007324),
            (-0.55, 0.006401),
            (-0.56, 0.005532),
            (-0.57, 0.004723),
            (-0.58, 0.003976),
            (-0.59, 0.003294),
            (-0.60, 0.002679),
            (-0.61, 0.002133),
            (-0.62, 0.001656),
            (-0.63, 0.001246),
            (-0.64, 0.000903),
            (-0.65, 0.000624),
            (-0.66, 0.000405),
            (-0.67, 0.000242),
            (-0.68, 0.000127),
            (-0.69, 0.000055),
            (-0.70, 0.000017),
            (-0.71, 0.000002),
            (-0.72, 0.000000),
        ]
        
        var totalWeight: CGFloat = 0.0
        var sumX: CGFloat = 0.0
        var sumY: CGFloat = 0.0
        
        for sample in sampleOffsets {
            let sampleTime = time + sample.dt
            guard sampleTime >= 0 else { continue }
            
            let sPos = stabilizedCursorPosition(at: sampleTime, from: events, fallback: basePoint)
            let target = computePushTarget(sPos)
            let w = CGFloat(sample.weight)
            sumX += target.x * w
            sumY += target.y * w
            totalWeight += w
        }
        
        if totalWeight > 0.0001 {
            let resX = sumX / totalWeight
            let resY = sumY / totalWeight
            return CGPoint(
                x: max(halfSpanX, min(1.0 - halfSpanX, resX)),
                y: max(halfSpanY, min(1.0 - halfSpanY, resY))
            )
        }
        
        let curPos = stabilizedCursorPosition(at: time, from: events, fallback: basePoint)
        let fallbackTarget = computePushTarget(curPos)
        return CGPoint(
            x: max(halfSpanX, min(1.0 - halfSpanX, fallbackTarget.x)),
            y: max(halfSpanY, min(1.0 - halfSpanY, fallbackTarget.y))
        )
    }
    
    /// Calculate the interpolated viewport (scale, center, 3D tilt, and dynamic motion blur) at any playback timestamp
    /// Supports seamless direct camera morphing between adjacent/abutting keyframes (FocuSee / Screen Studio style)
    public func evaluateViewport(
        at time: TimeInterval,
        sourceTime: TimeInterval? = nil,
        with keyframes: [ZoomKeyframe],
        telemetry: [TelemetryEvent] = []
    ) -> ViewportState {
        guard !keyframes.isEmpty else { return .fullScreen }
        
        let timeOffset = (sourceTime != nil) ? (sourceTime! - time) : 0.0
        
        // Pre-filter valid events once per evaluation and ensure strictly sorted order
        let validEvents = telemetry.filter { $0.position != nil }.sorted { $0.timestamp < $1.timestamp }
        let sortedKFs = keyframes.sorted { $0.startTime < $1.startTime }
        
        let adjacencyThreshold: TimeInterval = 2.0
        
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
            var holdStart: TimeInterval
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
            
            // Guarantee holdStart is clamped inside keyframe active boundary
            holdStart = min(kf.startTime + kf.duration, max(kf.startTime, holdStart))
            
            var effectiveMorphStart = morphStart
            var effectiveMorphEnd = morphEnd
            var effectiveZoomOutStart = zoomOutStart
            var effectiveZoomOutEnd = zoomOutEnd
            
            let holdEnd: TimeInterval
            if nextKF != nil {
                effectiveMorphStart = max(holdStart, morphStart)
                effectiveMorphEnd = max(effectiveMorphStart + 0.001, morphEnd)
                holdEnd = effectiveMorphStart
            } else {
                effectiveZoomOutStart = max(holdStart, zoomOutStart)
                effectiveZoomOutEnd = max(effectiveZoomOutStart + 0.001, zoomOutEnd)
                holdEnd = effectiveZoomOutStart
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
                let targetFocus = smoothCameraFocus(at: zoomInEnd + timeOffset, from: validEvents, basePoint: kf.focusPoint, scale: kf.scale)
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
                let activeFocus = smoothCameraFocus(at: time + timeOffset, from: validEvents, basePoint: kf.focusPoint, scale: kf.scale)
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
            if let next = nextKF, time >= effectiveMorphStart && time <= effectiveMorphEnd {
                let progress = (time - effectiveMorphStart) / max(0.001, effectiveMorphEnd - effectiveMorphStart)
                let eased = easyEaseInOut(progress)
                let currentScale = kf.scale + (next.scale - kf.scale) * CGFloat(eased)
                
                // Continuous Dynamic Radar Tracking Across Block Boundaries:
                // Evaluates live Steadicam cursor focus at current timestamp (time + timeOffset) for both blocks,
                // smoothly blending the base-point framing without ever freezing velocity or interrupting tracking!
                let focusA = smoothCameraFocus(at: time + timeOffset, from: validEvents, basePoint: kf.focusPoint, scale: currentScale)
                let focusB = smoothCameraFocus(at: time + timeOffset, from: validEvents, basePoint: next.focusPoint, scale: currentScale)
                
                let currentFocus = CGPoint(
                    x: focusA.x + (focusB.x - focusA.x) * CGFloat(eased),
                    y: focusA.y + (focusB.y - focusA.y) * CGFloat(eased)
                )
                
                let is3D_prev = kf.effectType == .motion3D
                let is3D_next = next.effectType == .motion3D
                let startAngles = is3D_prev ? kf.tiltPreset.angles(
                    focusPoint: focusA,
                    customPitch: kf.customPitch,
                    customYaw: kf.customYaw,
                    customRoll: kf.customRoll
                ) : (pitch: 0.0, yaw: 0.0, roll: 0.0)
                
                let endAngles = is3D_next ? next.tiltPreset.angles(
                    focusPoint: focusB,
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
            if !hasNextAdjacent && time >= effectiveZoomOutStart && time <= effectiveZoomOutEnd {
                let durationOut = max(0.001, effectiveZoomOutEnd - effectiveZoomOutStart)
                let progress = (time - effectiveZoomOutStart) / durationOut
                let eased = easyEaseInOut(progress)
                let currentScale = kf.scale - (kf.scale - 1.0) * CGFloat(eased)
                // Origin anchor at start of zoom-out (fixed anchor eliminates wobble during departure)
                let startFocus = smoothCameraFocus(at: effectiveZoomOutStart + timeOffset, from: validEvents, basePoint: kf.focusPoint, scale: kf.scale)
                
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
    
    /// Cinematic Cubic Easy-Ease function (matching After Effects / Screen Studio camera moves)
    /// Smooth velocity at start (zero velocity jerk), immediate natural response without 150ms deadzone, and velvety landing.
    private func easyEaseInOut(_ t: Double) -> Double {
        let x = min(max(t, 0.0), 1.0)
        // Cubic smoothstep: 3x^2 - 2x^3 provides smooth velocity without quintic freezing lag
        return x * x * (3.0 - 2.0 * x)
    }
}
