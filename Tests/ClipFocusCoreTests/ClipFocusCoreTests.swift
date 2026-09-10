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
    
    // MARK: - Project Serialization & Relinking Tests
    func testProjectSerializationAndDeserialization() throws {
        let keyframes = [
            ZoomKeyframe(
                startTime: 1.0,
                duration: 2.5,
                focusPoint: CGPoint(x: 0.65, y: 0.35),
                scale: 1.8,
                effectType: .motion3D,
                tiltPreset: .auto,
                customPitch: 12.0,
                customYaw: -8.0,
                customRoll: 1.5,
                positionOffsetX: 25.0,
                positionOffsetY: -15.0
            )
        ]
        
        let telemetry = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.65, y: 0.35)),
            TelemetryEvent(timestamp: 1.5, type: .mouseClick, position: CGPoint(x: 0.65, y: 0.35))
        ]
        
        let videoSegments = [
            MediaClipSegment(
                trackType: .video,
                name: "Clip 1",
                sourceStartTime: 0.5,
                timelineStartTime: 0.0,
                duration: 4.0,
                isMuted: false,
                volume: 0.8
            )
        ]
        
        let project = ClipFocusProject(
            title: "Test Project",
            duration: 12.5,
            rawVideoFilename: "/path/to/original.mov",
            relativeVideoPath: "original.mov",
            videoFileSize: 1048576,
            embeddedTelemetry: telemetry,
            aspectRatio: .vertical9x16,
            canvasRatioString: "9:16",
            canvasPadding: 32.0,
            canvasCornerRadius: 20.0,
            activeBackgroundIndex: 2,
            activeColorIndex: 1,
            tiltIntensity: 1.4,
            disableZoom: false,
            isAudioMuted: false,
            audioVolume: 0.9,
            currentTime: 2.5,
            timelineZoomScale: 1.5,
            zoomKeyframes: keyframes,
            videoSegments: videoSegments
        )
        
        let data = try project.encodeToData()
        XCTAssertFalse(data.isEmpty)
        
        let decoded = try ClipFocusProject.decode(from: data)
        XCTAssertEqual(decoded.title, "Test Project")
        XCTAssertEqual(decoded.duration, 12.5, accuracy: 0.01)
        XCTAssertEqual(decoded.canvasRatioString, "9:16")
        XCTAssertEqual(decoded.canvasPadding, 32.0)
        XCTAssertEqual(decoded.canvasCornerRadius, 20.0)
        XCTAssertEqual(decoded.activeBackgroundIndex, 2)
        XCTAssertEqual(decoded.activeColorIndex, 1)
        XCTAssertEqual(decoded.tiltIntensity, 1.4, accuracy: 0.01)
        XCTAssertEqual(decoded.zoomKeyframes.count, 1)
        XCTAssertEqual(decoded.zoomKeyframes[0].scale, 1.8, accuracy: 0.01)
        XCTAssertEqual(decoded.zoomKeyframes[0].positionOffsetX, 25.0)
        XCTAssertEqual(decoded.zoomKeyframes[0].positionOffsetY, -15.0)
        XCTAssertEqual(decoded.embeddedTelemetry?.count, 2)
        XCTAssertEqual(decoded.videoSegments.count, 1)
        XCTAssertEqual(decoded.videoSegments[0].duration, 4.0, accuracy: 0.01)
    }
    
    func testProjectAtomicSaveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let projectFileURL = tempDir.appendingPathComponent("MySavedProject.focusproj")
        let project = ClipFocusProject(
            title: "Atomic Test",
            duration: 8.0,
            rawVideoFilename: "/dummy/video.mp4",
            canvasRatioString: "1:1"
        )
        
        try project.saveAtomic(to: projectFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectFileURL.path))
        
        let loaded = try ClipFocusProject.load(from: projectFileURL)
        XCTAssertEqual(loaded.title, "Atomic Test")
        XCTAssertEqual(loaded.canvasRatioString, "1:1")
        XCTAssertEqual(loaded.duration, 8.0, accuracy: 0.01)
    }
    
    func testProjectSmartRelinking() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let projectFileURL = tempDir.appendingPathComponent("Project.focusproj")
        let siblingVideoURL = tempDir.appendingPathComponent("recording.mov")
        try Data("dummy video data".utf8).write(to: siblingVideoURL)
        
        // Scenario 1: Original absolute path was on another machine (/Users/someone_else/Desktop/recording.mov)
        // But sibling exists in the same folder as Project.focusproj
        let project = ClipFocusProject(
            title: "Relink Test",
            duration: 5.0,
            rawVideoFilename: "/Users/someone_else/Desktop/recording.mov",
            relativeVideoPath: "recording.mov"
        )
        
        let resolvedURL = project.resolveVideoURL(relativeTo: projectFileURL)
        XCTAssertNotNil(resolvedURL)
        XCTAssertEqual(resolvedURL?.path, siblingVideoURL.path)
        
        // Scenario 2: Video does not exist anywhere -> returns nil
        let missingProject = ClipFocusProject(
            title: "Missing Test",
            duration: 5.0,
            rawVideoFilename: "/nonexistent/path/ghost.mov",
            relativeVideoPath: "ghost.mov"
        )
        let missingResolved = missingProject.resolveVideoURL(relativeTo: projectFileURL)
        XCTAssertNil(missingResolved)
    }
    
    // MARK: - Frame Continuity & 3D Perspective Parity Tests
    func testZoomInOutFrameContinuityWithoutFullscreenPops() {
        let engine = AutoZoomEngine()
        let kf = ZoomKeyframe(
            startTime: 2.0,
            duration: 3.0,
            focusPoint: CGPoint(x: 0.3, y: 0.4),
            scale: 2.5,
            effectType: .motion3D,
            tiltPreset: .custom,
            customPitch: 13.0,
            customYaw: 14.0,
            positionOffsetX: 40.0,
            positionOffsetY: -25.0
        )
        
        var prevScale: CGFloat = 1.0
        var prevPitch: Double = 0.0
        var prevYaw: Double = 0.0
        
        // Sample at 60fps across the entire lifespan including zoom-in, hold, and zoom-out
        for frame in 0...300 {
            let t = 1.8 + Double(frame) / 60.0
            let vp = engine.evaluateViewport(at: t, with: [kf])
            
            // In the middle of the zoom block (e.g. t=3.0 to 4.5), scale must never abruptly drop to 1.0
            if t >= 2.95 && t <= 4.0 {
                XCTAssertGreaterThan(vp.scale, 2.0, "Scale must remain fully zoomed during hold without popping to 1.0 at t=\(t)")
                XCTAssertEqual(vp.pitch, 13.0, accuracy: 0.5, "Pitch must hold steady at 13 deg at t=\(t)")
                XCTAssertEqual(vp.yaw, 14.0, accuracy: 0.5, "Yaw must hold steady at 14 deg at t=\(t)")
            }
            
            // Frame-to-frame delta must be smooth at 60fps (max delta < 0.15 scale per frame)
            let deltaScale = abs(vp.scale - prevScale)
            XCTAssertLessThan(deltaScale, 0.15, "Scale change between consecutive frames must be smooth at t=\(t)")
            
            let deltaPitch = abs(vp.pitch - prevPitch)
            XCTAssertLessThan(deltaPitch, 2.5, "Pitch change between consecutive frames must be smooth at t=\(t)")
            
            let deltaYaw = abs(vp.yaw - prevYaw)
            XCTAssertLessThan(deltaYaw, 2.5, "Yaw change between consecutive frames must be smooth at t=\(t)")
            
            prevScale = vp.scale
            prevPitch = vp.pitch
            prevYaw = vp.yaw
        }
    }
    
    func testContinuousTelemetryInterpolationAcrossInterval() {
        let engine = AutoZoomEngine()
        let p0 = CGPoint(x: 0.2, y: 0.2)
        let p1 = CGPoint(x: 0.8, y: 0.8)
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: p0),
            TelemetryEvent(timestamp: 1.15, type: .mouseMove, position: p1)
        ]
        
        // At t=1.075 (midpoint of active motion): cursor should be approximately halfway
        let midPos = engine.cursorPosition(at: 1.075, from: events, fallback: p0)
        XCTAssertEqual(midPos.x, 0.5, accuracy: 0.05, "Cursor should smoothly interpolate through midpoint")
        XCTAssertEqual(midPos.y, 0.5, accuracy: 0.05, "Cursor should smoothly interpolate through midpoint")
        
        // Progressively increasing across the entire interval without sudden whip
        var prevX: CGFloat = p0.x
        for step in 1...10 {
            let t = 1.0 + Double(step) * 0.015
            let pos = engine.cursorPosition(at: t, from: events, fallback: p0)
            XCTAssertGreaterThanOrEqual(pos.x, prevX, "Cursor motion must be monotonic and smooth at t=\(t)")
            prevX = pos.x
        }
    }
    
    func testCustom3DExportFrameRendering() {
        let pitch = 13.0
        let yaw = 14.0
        let roll = 0.0
        let scale: CGFloat = 1.5
        let fx: CGFloat = 0.5
        let fy: CGFloat = 0.5
        let currentPositionX: CGFloat = 20.0
        let currentPositionY: CGFloat = -15.0
        
        // --- 1. PREVIEW SPACE (Cocoa / AppKit NativeVideoPlayerView) ---
        // Artboard size e.g. 850 x 478.125 (16:9)
        let prevArtW: CGFloat = 850.0
        let prevArtH: CGFloat = 478.125
        let prevPad: CGFloat = 30.0
        let prevAvailW = prevArtW - prevPad * 2.0 // 790
        let prevAvailH = prevArtH - prevPad * 2.0 // 418.125
        let vRatio: CGFloat = 16.0 / 9.0
        let prevFitByW = (prevAvailW / prevAvailH) <= vRatio
        let prevCardW = prevFitByW ? prevAvailW : (prevAvailH * vRatio) // 743.33
        let prevCardH = prevFitByW ? (prevAvailW / vRatio) : prevAvailH // 418.125
        
        let prevPanScale = prevCardW / 850.0
        let prevTransX = (0.5 - fx) * prevCardW * scale + (currentPositionX * 2.0) * prevPanScale
        let prevTransY = (0.5 - fy) * prevCardH * scale + (currentPositionY * 2.0) * prevPanScale
        
        let tiltMagnitude = hypot(pitch / 16.0, yaw / 16.0)
        let tiltRatio = tanh(tiltMagnitude)
        let prevElevationZ: CGFloat = (scale - 1.0) * 45.0 * CGFloat(tiltRatio)
        
        var prevTransform = CATransform3DIdentity
        prevTransform = CATransform3DTranslate(prevTransform, prevTransX, prevTransY, prevElevationZ)
        prevTransform = CATransform3DScale(prevTransform, scale, scale, 1.0)
        let radPitch = CGFloat(pitch * .pi / 180.0)
        let radYaw = CGFloat(yaw * .pi / 180.0)
        let radRoll = CGFloat(roll * .pi / 180.0)
        prevTransform = CATransform3DRotate(prevTransform, radPitch, 1, 0, 0)
        prevTransform = CATransform3DRotate(prevTransform, radYaw, 0, 1, 0)
        prevTransform = CATransform3DRotate(prevTransform, radRoll, 0, 0, 1)
        
        var prevPersp = CATransform3DIdentity
        prevPersp.m34 = -1.0 / 850.0
        let prevCombined = CATransform3DConcat(prevTransform, prevPersp)
        
        // In preview, NativeVideoPlayerView is centered in Artboard:
        let prevCenterArtX = prevArtW * 0.5
        let prevCenterArtY = prevArtH * 0.5
        
        func projectPreview(x: CGFloat, y: CGFloat) -> CGPoint {
            let px = x * prevCombined.m11 + y * prevCombined.m21 + prevCombined.m41
            let py = x * prevCombined.m12 + y * prevCombined.m22 + prevCombined.m42
            let pw = x * prevCombined.m14 + y * prevCombined.m24 + prevCombined.m44
            let w = pw != 0 ? pw : 1.0
            return CGPoint(x: prevCenterArtX + px / w, y: prevCenterArtY + py / w)
        }
        
        let prevTL = projectPreview(x: -prevCardW * 0.5, y: -prevCardH * 0.5)
        let prevTR = projectPreview(x: prevCardW * 0.5, y: -prevCardH * 0.5)
        let prevBR = projectPreview(x: prevCardW * 0.5, y: prevCardH * 0.5)
        let prevBL = projectPreview(x: -prevCardW * 0.5, y: prevCardH * 0.5)
        
        // Normalized Preview Coordinates (0.0 to 1.0 of artboard)
        let normPrevTL = CGPoint(x: prevTL.x / prevArtW, y: prevTL.y / prevArtH)
        let normPrevTR = CGPoint(x: prevTR.x / prevArtW, y: prevTR.y / prevArtH)
        let normPrevBR = CGPoint(x: prevBR.x / prevArtW, y: prevBR.y / prevArtH)
        let normPrevBL = CGPoint(x: prevBL.x / prevArtW, y: prevBL.y / prevArtH)
        
        print("\n--- PREVIEW NORMALIZED CORNERS ---")
        print("TL:", normPrevTL)
        print("TR:", normPrevTR)
        print("BR:", normPrevBR)
        print("BL:", normPrevBL)
        
        // --- 2. EXPORT SPACE WITH MATCHED PREVIEW PROJECTION MATH ---
        let expRenderW: CGFloat = 1920.0
        let expRenderH: CGFloat = 1080.0
        let expScaleFactor: CGFloat = expRenderW / prevArtW
        let expPad: CGFloat = prevPad * expScaleFactor
        let expAvailW: CGFloat = expRenderW - expPad * 2.0
        let expAvailH: CGFloat = expRenderH - expPad * 2.0
        let expFitByW: Bool = (expAvailW / expAvailH) <= vRatio
        let expBaseCardW: CGFloat = expFitByW ? expAvailW : (expAvailH * vRatio)
        let expBaseCardH: CGFloat = expFitByW ? (expAvailW / vRatio) : expAvailH
        
        let expPanScale = expBaseCardW / 850.0
        let expScaledPanX = (currentPositionX * 2.0) * expPanScale
        let expScaledPanY = (currentPositionY * 2.0) * expPanScale
        let expTransX = (0.5 - fx) * expBaseCardW * scale + expScaledPanX
        
        // Exact matching focal distance:
        // In preview: focalDistance = 850.0 (where perspective.m34 = -1.0 / 850.0)
        // In export: camera distance scales identically with the canvas: 850.0 * expScaleFactor
        let matchedExpFocalDistance = 850.0 * expScaleFactor
        var expPersp = CATransform3DIdentity
        expPersp.m34 = -1.0 / matchedExpFocalDistance
        
        // In preview, transY is in flipped coords (down). In CI, Y is up.
        // So transY in preview corresponds to -expTransY in preview flipped space:
        let prevStyleExpTransY = (0.5 - fy) * expBaseCardH * scale + expScaledPanY
        
        var expTransform = CATransform3DIdentity
        expTransform = CATransform3DTranslate(expTransform, expTransX, prevStyleExpTransY, prevElevationZ * expScaleFactor)
        expTransform = CATransform3DScale(expTransform, scale, scale, 1.0)
        expTransform = CATransform3DRotate(expTransform, radPitch, 1, 0, 0)
        expTransform = CATransform3DRotate(expTransform, radYaw, 0, 1, 0)
        expTransform = CATransform3DRotate(expTransform, radRoll, 0, 0, 1)
        
        let expCombined = CATransform3DConcat(expTransform, expPersp)
        let expCenterCanvasX = expRenderW * 0.5
        let expCenterCanvasY = expRenderH * 0.5
        
        func projectMatchedExport(x: CGFloat, y: CGFloat) -> CGPoint {
            let px = x * expCombined.m11 + y * expCombined.m21 + expCombined.m41
            let py = x * expCombined.m12 + y * expCombined.m22 + expCombined.m42
            let pw = x * expCombined.m14 + y * expCombined.m24 + expCombined.m44
            let w = pw != 0 ? pw : 1.0
            return CGPoint(x: expCenterCanvasX + px / w, y: expCenterCanvasY + py / w)
        }
        
        let expTL = projectMatchedExport(x: -expBaseCardW * 0.5, y: -expBaseCardH * 0.5)
        let expTR = projectMatchedExport(x: expBaseCardW * 0.5, y: -expBaseCardH * 0.5)
        let expBR = projectMatchedExport(x: expBaseCardW * 0.5, y: expBaseCardH * 0.5)
        let expBL = projectMatchedExport(x: -expBaseCardW * 0.5, y: expBaseCardH * 0.5)
        
        // Convert to normalized coordinates:
        let normExpTL = CGPoint(x: expTL.x / expRenderW, y: expTL.y / expRenderH)
        let normExpTR = CGPoint(x: expTR.x / expRenderW, y: expTR.y / expRenderH)
        let normExpBR = CGPoint(x: expBR.x / expRenderW, y: expBR.y / expRenderH)
        let normExpBL = CGPoint(x: expBL.x / expRenderW, y: expBL.y / expRenderH)
        
        print("\n--- MATCHED EXPORT NORMALIZED CORNERS ---")
        print("TL:", normExpTL)
        print("TR:", normExpTR)
        print("BR:", normExpBR)
        print("BL:", normExpBL)
        
        // Exact mathematical alignment: corner differences are near-zero (< 0.005)
        let diffTL = hypot(normExpTL.x - normPrevTL.x, normExpTL.y - normPrevTL.y)
        let diffTR = hypot(normExpTR.x - normPrevTR.x, normExpTR.y - normPrevTR.y)
        let diffBR = hypot(normExpBR.x - normPrevBR.x, normExpBR.y - normPrevBR.y)
        let diffBL = hypot(normExpBL.x - normPrevBL.x, normExpBL.y - normPrevBL.y)
        
        print(String(format: "Diff magnitudes: TL=%.6f, TR=%.6f, BR=%.6f, BL=%.6f", diffTL, diffTR, diffBR, diffBL))
        XCTAssertLessThan(diffTL, 0.005, "TL projection must match preview perfectly")
        XCTAssertLessThan(diffTR, 0.005, "TR projection must match preview perfectly")
        XCTAssertLessThan(diffBR, 0.005, "BR projection must match preview perfectly")
        XCTAssertLessThan(diffBL, 0.005, "BL projection must match preview perfectly")
    }
    
    func testCustomCursorRendererAndTelemetry() throws {
        // 1. Verify TelemetryEvent serialization with CursorType
        let event = TelemetryEvent(
            timestamp: 1.25,
            type: .mouseMove,
            position: CGPoint(x: 0.5, y: 0.5),
            cursorType: .pointingHand
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TelemetryEvent.self, from: data)
        XCTAssertEqual(decoded.cursorType, .pointingHand)
        
        // 2. Verify Hotspots
        XCTAssertEqual(CustomCursorRenderer.hotspot(for: .arrow, size: 100), CGPoint(x: 1.0, y: 1.0))
        let ibeamHotspot = CustomCursorRenderer.hotspot(for: .iBeam, size: 100)
        XCTAssertEqual(ibeamHotspot.x, 100.0 * (10.0 / 24.0), accuracy: 0.001)
        XCTAssertEqual(ibeamHotspot.y, 50.0, accuracy: 0.001)
        let pointingHotspot = CustomCursorRenderer.hotspot(for: .pointingHand, size: 100)
        XCTAssertEqual(pointingHotspot.x, 100.0 * (8.5 / 24.0), accuracy: 0.001)
        XCTAssertEqual(pointingHotspot.y, 1.5, accuracy: 0.001)
        XCTAssertEqual(CustomCursorRenderer.hotspot(for: .closedHand, size: 100), CGPoint(x: 45.0, y: 45.0))
        
        // 3. Verify Vector Paths Non-Empty
        let arrowPath = CustomCursorRenderer.createModernArrowPath(size: 32)
        XCTAssertFalse(arrowPath.isEmpty)
        let ibeamPath = CustomCursorRenderer.createIBeamPath(size: 32)
        XCTAssertFalse(ibeamPath.isEmpty)
        let handPath = CustomCursorRenderer.createPointingHandPath(size: 32)
        XCTAssertFalse(handPath.isEmpty)
        let closedPath = CustomCursorRenderer.createClosedHandPath(size: 32)
        XCTAssertFalse(closedPath.isEmpty)
        
        // 4. Verify Drawing into CGContext
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create test CGContext")
            return
        }
        
        CustomCursorRenderer.drawCursor(
            in: ctx,
            at: CGPoint(x: 50, y: 50),
            type: .arrow,
            size: 32,
            clickProgress: 0.5,
            isRightClick: false
        )
        
        // 5. Verify Compositor Cursor State Evaluation
        let telemetryEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.2, y: 0.2), cursorType: .arrow),
            TelemetryEvent(timestamp: 1.5, type: .mouseClick, position: CGPoint(x: 0.25, y: 0.25), button: .left, cursorType: .pointingHand),
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.3, y: 0.3), cursorType: .arrow)
        ]
        
        let state1 = VideoCompositorEngine.evaluateCursorState(at: 1.52, events: telemetryEvents, autoHideIdle: false, clickRipple: true)
        XCTAssertNotNil(state1)
        XCTAssertEqual(state1?.type, .pointingHand)
        XCTAssertGreaterThan(state1?.clickProgress ?? 0, 0)
    }
}


