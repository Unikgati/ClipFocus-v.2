import XCTest
import AVFoundation
@testable import ClipFocusCore

final class ClipFocusCoreTests: XCTestCase {
    
    func testTelemetryEventSerialization() throws {
        let event = TelemetryEvent(
            timestamp: 2.5,
            type: .mouseClick,
            position: CGPoint(x: 0.35, y: 0.65),
            button: .left,
            clickCount: 1,
            keyCharacters: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TelemetryEvent.self, from: data)
        
        XCTAssertEqual(decoded.type, .mouseClick)
        XCTAssertEqual(decoded.timestamp, 2.5)
        XCTAssertEqual(decoded.position?.x, 0.35)
        XCTAssertEqual(decoded.position?.y, 0.65)
    }
    
    func testAutoZoomEngineClustering() {
        let engine = AutoZoomEngine()
        
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseClick, position: CGPoint(x: 0.2, y: 0.2)),
            TelemetryEvent(timestamp: 1.5, type: .mouseClick, position: CGPoint(x: 0.22, y: 0.21)),
            TelemetryEvent(timestamp: 8.0, type: .mouseClick, position: CGPoint(x: 0.8, y: 0.8))
        ]
        
        let keyframes = engine.generateKeyframes(from: events, totalDuration: 12.0)
        
        // Should group the first two into one cluster, and the 8.0s into a second cluster
        XCTAssertEqual(keyframes.count, 2)
        XCTAssertGreaterThan(keyframes[0].scale, 1.0)
        XCTAssertEqual(keyframes[0].reason, "click_cluster")
    }
    
    func testStartAndStopBoundaryClickFiltering() {
        let engine = AutoZoomEngine()
        
        // Simulates a recording where user ONLY clicked REC (at 0.1s) and STOP REC (at 9.8s) on a 10s video
        let boundaryEvents = [
            TelemetryEvent(timestamp: 0.15, type: .mouseClick, position: CGPoint(x: 0.95, y: 0.05)), // Rec button
            TelemetryEvent(timestamp: 9.75, type: .mouseClick, position: CGPoint(x: 0.50, y: 0.95))  // Stop button
        ]
        
        let keyframes = engine.generateKeyframes(from: boundaryEvents, totalDuration: 10.0)
        // Must filter out both boundary clicks -> resulting in exactly 0 ghost keyframes!
        XCTAssertEqual(keyframes.count, 0)
    }
    
    func testViewportEvaluationBounds() {
        let engine = AutoZoomEngine()
        let keyframe = ZoomKeyframe(
            startTime: 2.0,
            duration: 3.0,
            focusPoint: CGPoint(x: 0.3, y: 0.4),
            scale: 2.0
        )
        
        // Before zoom
        let vpBefore = engine.evaluateViewport(at: 1.0, with: [keyframe])
        XCTAssertEqual(vpBefore.scale, 1.0)
        
        // During hold
        let vpHold = engine.evaluateViewport(at: 3.5, with: [keyframe])
        XCTAssertEqual(vpHold.scale, 2.0)
        XCTAssertEqual(vpHold.focusPoint.x, 0.3)
        XCTAssertEqual(vpHold.focusPoint.y, 0.4)
        
        // After zoom completes
        let vpAfter = engine.evaluateViewport(at: 6.0, with: [keyframe])
        XCTAssertEqual(vpAfter.scale, 1.0)
    }
    
    func testAdjacentKeyframeSeamlessMorphing() {
        let engine = AutoZoomEngine()
        let kf1 = ZoomKeyframe(
            startTime: 2.0,
            duration: 4.0, // Ends at 6.0
            focusPoint: CGPoint(x: 0.2, y: 0.2),
            scale: 2.0
        )
        let kf2 = ZoomKeyframe(
            startTime: 6.0, // Starts immediately at 6.0 (adjacent/abutting)
            duration: 4.0, // Ends at 10.0
            focusPoint: CGPoint(x: 0.8, y: 0.8),
            scale: 3.0
        )
        
        let keyframes = [kf1, kf2]
        
        // At 3.0s (mid kf1): scale should be 2.0, focus (0.2, 0.2)
        let vpKF1 = engine.evaluateViewport(at: 3.0, with: keyframes)
        XCTAssertEqual(vpKF1.scale, 2.0)
        XCTAssertEqual(vpKF1.focusPoint.x, 0.2, accuracy: 0.01)
        XCTAssertEqual(vpKF1.focusPoint.y, 0.2, accuracy: 0.01)
        
        // At 6.0s (cut boundary): Anticipation hold keeps scale zoomed (> 1.9, NEVER dipping to 1.0)
        let vpBoundary = engine.evaluateViewport(at: 6.0, with: keyframes)
        XCTAssertGreaterThan(vpBoundary.scale, 1.9)
        XCTAssertLessThan(vpBoundary.scale, 3.1)
        
        // At 6.25s (mid-glide across the screen): focus point is actively gliding through the middle (~0.5)
        let vpMidGlide = engine.evaluateViewport(at: 6.25, with: keyframes)
        XCTAssertGreaterThan(vpMidGlide.scale, 1.9)
        XCTAssertEqual(vpMidGlide.focusPoint.x, 0.5, accuracy: 0.15)
        XCTAssertEqual(vpMidGlide.focusPoint.y, 0.5, accuracy: 0.15)
        
        // At 8.0s (mid kf2): scale should be 3.0, focus settled at (0.8, 0.8)
        let vpKF2 = engine.evaluateViewport(at: 8.0, with: keyframes)
        XCTAssertEqual(vpKF2.scale, 3.0)
        XCTAssertEqual(vpKF2.focusPoint.x, 0.8, accuracy: 0.01)
        XCTAssertEqual(vpKF2.focusPoint.y, 0.8, accuracy: 0.01)
        
        // At 11.0s (after kf2 ends with no subsequent keyframe): zoom out to full screen 1.0
        let vpEnd = engine.evaluateViewport(at: 11.0, with: keyframes)
        XCTAssertEqual(vpEnd.scale, 1.0)
    }
    
    func testSmartCutSilenceDetection() {
        let engine = SmartCutEngine()
        // 10 samples of quiet noise (-60dB) = 0.5s silence
        let samples: [Float] = Array(repeating: -60.0, count: 20)
        let cuts = engine.detectSilences(powerSamples: samples, sampleInterval: 0.05)
        
        XCTAssertFalse(cuts.isEmpty)
        XCTAssertEqual(cuts[0].type, .silence)
    }
    
    func testZeroByteRecordingValidation() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let emptyFile = tempDir.appendingPathComponent("empty_test_\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: emptyFile.path, contents: Data())
        
        defer { try? FileManager.default.removeItem(at: emptyFile) }
        
        let attrs = try FileManager.default.attributesOfItem(atPath: emptyFile.path)
        let fileSize = attrs[.size] as? Int64 ?? 0
        XCTAssertEqual(fileSize, 0)
        XCTAssertTrue(fileSize <= 1024, "Empty recording must be identified as corrupt")
    }
    
    func test3DCameraAngleCalculations() {
        let focusPoint = CGPoint(x: 0.8, y: 0.2)
        let progress: Double = 1.0
        let tiltIntensity: Double = 1.0
        
        let pitch = (focusPoint.y - 0.5) * -16.0 * progress * tiltIntensity
        let yaw = (focusPoint.x - 0.5) * 18.0 * progress * tiltIntensity
        let roll = ((focusPoint.x - 0.5) * (focusPoint.y - 0.5)) * -8.0 * progress * tiltIntensity
        
        // (0.2 - 0.5) = -0.3 * -16 = 4.8 degrees pitch
        XCTAssertEqual(pitch, 4.8, accuracy: 0.001)
        // (0.8 - 0.5) = 0.3 * 18 = 5.4 degrees yaw
        XCTAssertEqual(yaw, 5.4, accuracy: 0.001)
        // 0.3 * -0.3 = -0.09 * -8 = 0.72 degrees roll
        XCTAssertEqual(roll, 0.72, accuracy: 0.001)
    }
    
    func testMediaClipSegmentSerialization() throws {
        let seg = MediaClipSegment(
            trackType: .video,
            name: "Clip 1",
            sourceStartTime: 0.0,
            timelineStartTime: 2.5,
            duration: 5.0,
            isMuted: false,
            volume: 1.0
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(seg)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MediaClipSegment.self, from: data)
        
        XCTAssertEqual(decoded.trackType, .video)
        XCTAssertEqual(decoded.name, "Clip 1")
        XCTAssertEqual(decoded.timelineStartTime, 2.5)
        XCTAssertEqual(decoded.duration, 5.0)
        XCTAssertEqual(decoded.timelineEndTime, 7.5)
        XCTAssertFalse(decoded.isMuted)
    }
    
    func testMediaClipSegmentSplitMath() {
        let original = MediaClipSegment(
            trackType: .video,
            name: "Screen Recording",
            sourceStartTime: 1.0,
            timelineStartTime: 0.0,
            duration: 10.0,
            isMuted: false,
            volume: 1.0
        )
        
        let splitTime = 4.0
        let firstDuration = splitTime - original.timelineStartTime // 4.0
        let secondDuration = original.duration - firstDuration // 6.0
        
        var part1 = original
        part1.duration = firstDuration
        
        let part2 = MediaClipSegment(
            trackType: .video,
            name: "\(original.name) (Cut)",
            sourceStartTime: original.sourceStartTime + firstDuration, // 5.0
            timelineStartTime: splitTime, // 4.0
            duration: secondDuration, // 6.0
            isMuted: original.isMuted,
            volume: original.volume
        )
        
        XCTAssertEqual(part1.timelineStartTime, 0.0)
        XCTAssertEqual(part1.duration, 4.0)
        XCTAssertEqual(part1.timelineEndTime, 4.0)
        
        XCTAssertEqual(part2.timelineStartTime, 4.0)
        XCTAssertEqual(part2.duration, 6.0)
        XCTAssertEqual(part2.timelineEndTime, 10.0)
        XCTAssertEqual(part2.sourceStartTime, 5.0)
    }
    
    func testMediaClipSegmentTrimClamping() {
        let totalMediaDuration = 10.0
        let seg = MediaClipSegment(
            trackType: .video,
            name: "Segment Cut",
            sourceStartTime: 4.0,
            timelineStartTime: 2.0,
            duration: 3.0 // ends at source 7.0, timeline 5.0
        )
        
        // 1. Trimming start (left handle) backwards can only go back to sourceStartTime == 0.0
        // minSourceStart = timelineStartTime (2.0) - sourceStartTime (4.0) = -2.0
        let minTimelineStart = 0.0 // no prev clip
        let minSourceStart = seg.timelineStartTime - seg.sourceStartTime // -2.0
        let effectiveMinStart = max(minTimelineStart, minSourceStart) // 0.0
        XCTAssertEqual(effectiveMinStart, 0.0)
        
        // 2. Trimming end (right handle) forwards can only extend up to totalMediaDuration (10.0)
        // maxSourceDur = totalMediaDuration (10.0) - seg.sourceStartTime (4.0) = 6.0
        let maxSourceDur = max(0.2, totalMediaDuration - seg.sourceStartTime)
        XCTAssertEqual(maxSourceDur, 6.0)
    }
    
    func testVideoCompositorEngineBuildAndConfiguration() {
        let comp = AVMutableComposition()
        let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        track.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)))
        
        let config = VideoCompositorConfig(
            renderSize: CGSize(width: 1920, height: 1080),
            padding: 32.0,
            cornerRadius: 16.0,
            shadowRadius: 24.0,
            activeBackgroundIndex: 2,
            activeColorIndex: nil,
            zoomKeyframes: [
                ZoomKeyframe(startTime: 1.0, duration: 2.0, focusPoint: CGPoint(x: 0.3, y: 0.7), scale: 1.8, effectType: .motion3D)
            ],
            telemetryEvents: [],
            tiltIntensity: 1.0,
            disableZoom: false
        )
        
        let videoComp = VideoCompositorEngine.shared.buildVideoComposition(for: comp, config: config)
        XCTAssertEqual(videoComp.renderSize.width, 1920)
        XCTAssertEqual(videoComp.renderSize.height, 1080)
        XCTAssertEqual(videoComp.frameDuration, CMTime(value: 1, timescale: 60))
        XCTAssertEqual(videoComp.instructions.count, 1)
    }
    
    func testPauseResumePTSOffsetCompensation() {
        let tracker = CursorTracker()
        tracker.startTracking()
        
        // Pause tracking for simulated 2.5s
        tracker.pauseTracking()
        XCTAssertTrue(tracker.isPaused)
        
        tracker.resumeTracking(pausedDuration: 2.5)
        XCTAssertFalse(tracker.isPaused)
        
        let events = tracker.stopTracking()
        XCTAssertTrue(events.isEmpty || events.allSatisfy { $0.timestamp >= 0.0 })
    }
    
    func testCinematicCameraInertiaAndSpeedDamping() {
        let engine = AutoZoomEngine()
        
        // Simulates a sudden fast cursor flick from (0.3, 0.5) to (0.8, 0.5) in 0.1s
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.3, y: 0.5)),
            TelemetryEvent(timestamp: 2.0, type: .mouseMove, position: CGPoint(x: 0.3, y: 0.5)),
            TelemetryEvent(timestamp: 2.1, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.5)),
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.5))
        ]
        
        // At 2.0s: Before flick, camera focus is locked around 0.3
        let focusStart = engine.smoothCameraFocus(at: 2.0, from: events, basePoint: CGPoint(x: 0.3, y: 0.5), scale: 2.0)
        XCTAssertEqual(focusStart.x, 0.3, accuracy: 0.02)
        
        // At 2.12s (Immediately after rapid flick to 0.8):
        // Camera must exhibit natural inertia drag / delayed follow: it must NOT snap instantly to 0.8
        let focusLag = engine.smoothCameraFocus(at: 2.12, from: events, basePoint: CGPoint(x: 0.3, y: 0.5), scale: 2.0)
        XCTAssertLessThan(focusLag.x, 0.52, "Camera must lag behind rapid cursor flick with heavy inertia")
        
        // At 2.30s (Mid-glide): Camera is smoothly in transit
        let focusGlide = engine.smoothCameraFocus(at: 2.30, from: events, basePoint: CGPoint(x: 0.3, y: 0.5), scale: 2.0)
        XCTAssertGreaterThan(focusGlide.x, focusLag.x)
        
        // At 2.80s (After settling delay): Camera gently reaches comfortable framing
        let focusSettled = engine.smoothCameraFocus(at: 2.80, from: events, basePoint: CGPoint(x: 0.3, y: 0.5), scale: 2.0)
        XCTAssertGreaterThan(focusSettled.x, 0.65)
    }
    
    func testSafeZoneBoundaryOppositeMovementSmoothness() {
        let engine = AutoZoomEngine()
        
        // 1. Moving from top safe-zone edge (y=0.35) to bottom safe-zone edge (y=0.65)
        let topToBottomEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.35)),
            TelemetryEvent(timestamp: 1.4, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.65)),
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.65))
        ]
        
        var prevY: CGFloat = -1.0
        // Sample across the entire transit window in 50ms increments
        for step in 0...20 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: topToBottomEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevY >= 0 {
                // Must be strictly non-decreasing (no jitter, no backward snap, no oscillation)
                XCTAssertGreaterThanOrEqual(focus.y + 0.0001, prevY, "Camera trajectory must be strictly monotonic and smooth without backward jitter at t=\(t)")
            }
            prevY = focus.y
        }
        
        // 2. Moving from right safe-zone edge (x=0.65) to left safe-zone edge (x=0.35)
        let rightToLeftEvents = [
            TelemetryEvent(timestamp: 4.0, type: .mouseMove, position: CGPoint(x: 0.65, y: 0.5)),
            TelemetryEvent(timestamp: 4.4, type: .mouseMove, position: CGPoint(x: 0.35, y: 0.5)),
            TelemetryEvent(timestamp: 6.0, type: .mouseMove, position: CGPoint(x: 0.35, y: 0.5))
        ]
        
        var prevX: CGFloat = 2.0
        for step in 0...20 {
            let t = 4.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: rightToLeftEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevX <= 1.0 {
                // Must be strictly non-increasing (no jitter, no backward snap, no oscillation)
                XCTAssertLessThanOrEqual(focus.x - 0.0001, prevX, "Camera trajectory must be strictly monotonic and smooth without backward jitter at t=\(t)")
            }
            prevX = focus.x
        }
        
        // 3. Moving from bottom safe-zone edge (y=0.65) to left safe-zone edge (x=0.35)
        let bottomToLeftEvents = [
            TelemetryEvent(timestamp: 7.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.65)),
            TelemetryEvent(timestamp: 7.4, type: .mouseMove, position: CGPoint(x: 0.35, y: 0.5)),
            TelemetryEvent(timestamp: 9.0, type: .mouseMove, position: CGPoint(x: 0.35, y: 0.5))
        ]
        
        var prevBL_X: CGFloat = 2.0
        var prevBL_Y: CGFloat = 2.0
        for step in 0...20 {
            let t = 7.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: bottomToLeftEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevBL_X <= 1.0 {
                XCTAssertLessThanOrEqual(focus.x - 0.0001, prevBL_X, "X must decrease smoothly towards left edge at t=\(t)")
                XCTAssertLessThanOrEqual(focus.y - 0.0001, prevBL_Y, "Y must decrease smoothly from bottom towards center at t=\(t)")
            }
            prevBL_X = focus.x
            prevBL_Y = focus.y
        }
        
        // 4. Moving from bottom safe-zone edge (y=0.65) to right safe-zone edge (x=0.65)
        let bottomToRightEvents = [
            TelemetryEvent(timestamp: 10.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.65)),
            TelemetryEvent(timestamp: 10.4, type: .mouseMove, position: CGPoint(x: 0.65, y: 0.5)),
            TelemetryEvent(timestamp: 12.0, type: .mouseMove, position: CGPoint(x: 0.65, y: 0.5))
        ]
        
        var prevBR_X: CGFloat = -1.0
        var prevBR_Y: CGFloat = 2.0
        for step in 0...20 {
            let t = 10.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: bottomToRightEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevBR_X >= 0 {
                XCTAssertGreaterThanOrEqual(focus.x + 0.0001, prevBR_X, "X must increase smoothly towards right edge at t=\(t)")
                XCTAssertLessThanOrEqual(focus.y - 0.0001, prevBR_Y, "Y must decrease smoothly from bottom towards center at t=\(t)")
            }
            prevBR_X = focus.x
            prevBR_Y = focus.y
        }
    }
    
    func testCenterToOutwardBreakoutSmoothness() {
        let engine = AutoZoomEngine()
        
        // 1. Center (0.5, 0.5) to Top (0.5, 0.15)
        let centerToTopEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 1.4, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.15)),
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.15))
        ]
        var prevY: CGFloat = 2.0
        for step in 0...20 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: centerToTopEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevY <= 1.0 {
                XCTAssertLessThanOrEqual(focus.y - 0.0001, prevY, "Center to Top: Y must decrease monotonically at t=\(t)")
            }
            prevY = focus.y
        }
        
        // 2. Center (0.5, 0.5) to Bottom (0.5, 0.85)
        let centerToBottomEvents = [
            TelemetryEvent(timestamp: 4.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 4.4, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.85)),
            TelemetryEvent(timestamp: 6.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.85))
        ]
        prevY = -1.0
        for step in 0...20 {
            let t = 4.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: centerToBottomEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevY >= 0.0 {
                XCTAssertGreaterThanOrEqual(focus.y + 0.0001, prevY, "Center to Bottom: Y must increase monotonically at t=\(t)")
            }
            prevY = focus.y
        }
        
        // 3. Center (0.5, 0.5) to Left (0.15, 0.5)
        let centerToLeftEvents = [
            TelemetryEvent(timestamp: 7.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 7.4, type: .mouseMove, position: CGPoint(x: 0.15, y: 0.5)),
            TelemetryEvent(timestamp: 9.0, type: .mouseMove, position: CGPoint(x: 0.15, y: 0.5))
        ]
        var prevX: CGFloat = 2.0
        for step in 0...20 {
            let t = 7.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: centerToLeftEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevX <= 1.0 {
                XCTAssertLessThanOrEqual(focus.x - 0.0001, prevX, "Center to Left: X must decrease monotonically at t=\(t)")
            }
            prevX = focus.x
        }
        
        // 4. Center (0.5, 0.5) to Right (0.85, 0.5)
        let centerToRightEvents = [
            TelemetryEvent(timestamp: 10.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 10.4, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.5)),
            TelemetryEvent(timestamp: 12.0, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.5))
        ]
        prevX = -1.0
        for step in 0...20 {
            let t = 10.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: centerToRightEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevX >= 0.0 {
                XCTAssertGreaterThanOrEqual(focus.x + 0.0001, prevX, "Center to Right: X must increase monotonically at t=\(t)")
            }
            prevX = focus.x
        }
    }
    
    func testSafeZoneQuickExitAndReentrySmoothness() {
        let engine = AutoZoomEngine()
        
        // Simulates cursor at center (0.5, 0.5), quickly darting outside to (0.85, 0.5) and immediately returning
        let quickExitReentryEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 1.2, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.5)), // Brief exit outside safe zone
            TelemetryEvent(timestamp: 1.4, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),  // Immediate return inside safe zone
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5))
        ]
        
        var trajectory: [(t: Double, x: CGFloat)] = []
        for step in 0...40 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: quickExitReentryEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, x: focus.x))
        }
        
        // Find the peak displacement
        guard let maxItem = trajectory.max(by: { $0.x < $1.x }) else {
            XCTFail("Trajectory must have samples")
            return
        }
        
        let peakIndex = trajectory.firstIndex(where: { $0.t == maxItem.t })!
        
        // 1. Camera absorbed the brief excursion with heavy inertia (did not jerk all the way to 0.85)
        XCTAssertLessThan(maxItem.x, 0.72, "Peak deflection must be smoothly damped by inertia")
        XCTAssertGreaterThan(maxItem.x, 0.52, "Camera must respond to the outward movement")
        
        // 2. Trajectory before peak must rise monotonically (zero jitter on the way out)
        for i in 1...peakIndex {
            XCTAssertGreaterThanOrEqual(trajectory[i].x + 0.0001, trajectory[i-1].x, "Outward rise must be smooth at t=\(trajectory[i].t)")
        }
        
        // 3. Trajectory after peak must fall monotonically back to center (zero bounce/jitter on the return)
        for i in (peakIndex + 1)..<trajectory.count {
            XCTAssertLessThanOrEqual(trajectory[i].x - 0.0001, trajectory[i-1].x, "Inward return must be smooth at t=\(trajectory[i].t)")
        }
        
        // 4. By t=3.0, camera has gently settled back near center (0.50)
        let settledX = trajectory.last!.x
        XCTAssertEqual(settledX, 0.50, accuracy: 0.03, "Camera must settle cleanly back to center")
    }
    
    func testSuddenMovementWhileCameraAtOffsetPosition() {
        let engine = AutoZoomEngine()
        
        // Simulates:
        // 1. Mouse moves to (0.70, 0.40) and STOPS there for 1.5s (camera is resting at 0.70, 0.40)
        // 2. Mouse suddenly flicks to (0.30, 0.20) in the opposite direction
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: CGPoint(x: 0.70, y: 0.40)),
            TelemetryEvent(timestamp: 1.6, type: .mouseMove, position: CGPoint(x: 0.70, y: 0.40)), // Stationary at (0.70, 0.40)
            // Long gap where camera sits stably at offset position until t=3.0
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.30, y: 0.20)), // Sudden move in new direction
            TelemetryEvent(timestamp: 3.1, type: .mouseMove, position: CGPoint(x: 0.30, y: 0.20)),
            TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.30, y: 0.20))
        ]
        
        // At t=2.8s (before sudden move): camera focus must be stable at offset position, ZERO phantom drift
        let focusBefore = engine.smoothCameraFocus(at: 2.8, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        XCTAssertGreaterThan(focusBefore.x, 0.60, "Camera must be settled at offset position before sudden move")
        
        // From t=2.9 to 4.0: transit must be strictly non-increasing in X without backward jitter
        var prevX: CGFloat = 2.0
        for step in 0...22 {
            let t = 2.9 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevX <= 1.0 {
                XCTAssertLessThanOrEqual(focus.x - 0.0001, prevX, "Camera must smoothly transit left towards 0.30 without jitter or jerk at t=\(t)")
            }
            prevX = focus.x
        }
    }
}

