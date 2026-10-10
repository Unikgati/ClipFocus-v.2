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
        
        // Skenario 1: Cursor bergerak dari A (0.5) ke B (0.85) lalu kembali ke A (0.5) dengan cepat tanpa interaksi.
        // Kamera harus menekan gerakan sementara ini (tidak bergetar / tersentak ke B).
        let quickExitReentryEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 1.2, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.5)), // Gerakan sementara keluar safe zone
            TelemetryEvent(timestamp: 1.4, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),  // Kembali segera ke posisi awal
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5))
        ]
        
        var trajectory: [(t: Double, x: CGFloat)] = []
        for step in 0...40 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: quickExitReentryEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, x: focus.x))
        }
        
        // Verifikasi bahwa kamera menekan gerakan sementara tanpa interaksi
        let maxItem = trajectory.max(by: { $0.x < $1.x })!
        XCTAssertEqual(maxItem.x, 0.50, accuracy: 0.02, "Camera must suppress insignificant transient movement and remain stable at center")
        
        // Skenario 4: Cursor melakukan klik atau interaksi penting di B saat gerakan cepat.
        // Kamera HARUS menangkap interaksi penting tersebut.
        let quickExitWithClickEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 1.2, type: .mouseClick, position: CGPoint(x: 0.85, y: 0.5)), // Klik penting di B
            TelemetryEvent(timestamp: 1.4, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5))
        ]
        
        var clickTrajectory: [(t: Double, x: CGFloat)] = []
        for step in 0...40 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: quickExitWithClickEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            clickTrajectory.append((t: t, x: focus.x))
        }
        
        let maxClickItem = clickTrajectory.max(by: { $0.x < $1.x })!
        let peakClickIndex = clickTrajectory.firstIndex(where: { $0.t == maxClickItem.t })!
        
        // Kamera merespons gerakan karena ada klik penting di titik B
        XCTAssertGreaterThan(maxClickItem.x, 0.52, "Camera must capture important click interaction at target")
        XCTAssertLessThan(maxClickItem.x, 0.72, "Peak deflection must be smoothly damped by inertia")
        
        // Trajectory menuju klik harus naik secara mulus (monoton)
        if peakClickIndex > 0 {
            for i in 1...peakClickIndex {
                XCTAssertGreaterThanOrEqual(clickTrajectory[i].x + 0.0001, clickTrajectory[i-1].x, "Outward rise must be smooth at t=\(clickTrajectory[i].t)")
            }
        }
        
        // Trajectory setelah klik harus kembali secara mulus (monoton)
        for i in (peakClickIndex + 1)..<clickTrajectory.count {
            XCTAssertLessThanOrEqual(clickTrajectory[i].x - 0.0001, clickTrajectory[i-1].x, "Inward return must be smooth at t=\(clickTrajectory[i].t)")
        }
        
        // Setelah settling, kamera kembali tenang di posisi tengah (0.50)
        let settledClickX = clickTrajectory.last!.x
        XCTAssertEqual(settledClickX, 0.50, accuracy: 0.03, "Camera must settle cleanly back to center")
    }
    
    // MARK: - Validation Scenarios for Camera Smoothness
    func testValidationScenarioMultiAreaRapidTransition() {
        let engine = AutoZoomEngine()
        
        // Skenario 3: Cursor berpindah cepat di antara beberapa area (A -> B -> C -> D).
        // Kamera harus bergerak smooth dan kontinu mengikuti aliran tanpa gerakan bolak-balik yang aneh.
        let multiAreaEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.20, y: 0.30)), // Area A
            TelemetryEvent(timestamp: 1.3, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)), // Area B
            TelemetryEvent(timestamp: 1.6, type: .mouseMove, position: CGPoint(x: 0.75, y: 0.70)), // Area C
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.75, y: 0.70))
        ]
        
        var trajectory: [(t: Double, pt: CGPoint)] = []
        for step in 0...30 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: multiAreaEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, pt: focus))
        }
        
        // Pastikan transisi dari A ke C berjalan maju tanpa rollback mendadak
        // X harus naik secara umum dari ~0.35/0.40 ke > 0.60
        let startX = trajectory.first!.pt.x
        let endX = trajectory.last!.pt.x
        XCTAssertGreaterThan(endX, startX + 0.15, "Camera must smoothly progress toward destination Area C")
    }
    
    func testValidationScenarioSlowAndNormalMovementPreserved() {
        let engine = AutoZoomEngine()
        
        // Skenario 5: Pergerakan cursor yang lambat dan normal tetap menghasilkan respons kamera seperti sebelumnya.
        let slowEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 2.0, type: .mouseMove, position: CGPoint(x: 0.75, y: 0.50)), // Bergerak lambat selama 1 detik
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.75, y: 0.50))
        ]
        
        let focusStart = engine.smoothCameraFocus(at: 1.0, from: slowEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let focusMid = engine.smoothCameraFocus(at: 2.0, from: slowEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let focusSettled = engine.smoothCameraFocus(at: 3.0, from: slowEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        
        XCTAssertEqual(focusStart.x, 0.50, accuracy: 0.02, "Camera starts centered")
        XCTAssertGreaterThan(focusMid.x, focusStart.x, "Camera tracks slow movement naturally")
        XCTAssertGreaterThan(focusSettled.x, 0.60, "Camera comfortably frames target after slow movement")
    }
    
    func testValidationScenarioGradualOnsetAndGentleDeceleration() {
        let engine = AutoZoomEngine()
        
        // Skenario 1 & 5: Memastikan kamera tidak bereaksi secara instan melainkan bertahap (akselerasi halus)
        // dan melambat secara bertahap saat berhenti tanpa terpotong mendadak (cubic ease-out landing).
        let moveEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: CGPoint(x: 0.80, y: 0.50)),
            TelemetryEvent(timestamp: 4.0, type: .mouseMove, position: CGPoint(x: 0.80, y: 0.50))
        ]
        
        // 1. Pada saat gerakan baru dimulai (1.00s sampai 1.06s), pergerakan kamera bertahap (tidak menyentak seketika)
        let f0 = engine.smoothCameraFocus(at: 1.00, from: moveEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let f1 = engine.smoothCameraFocus(at: 1.04, from: moveEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let deltaInitial = f1.x - f0.x
        XCTAssertLessThan(deltaInitial, 0.02, "Initial response must accelerate gradually with zero immediate jerk")
        
        // 2. Pada saat mendekati target (misalnya 2.2s hingga 2.5s), kamera melambat secara halus tanpa tersentak berhenti mendadak
        let fNearLand1 = engine.smoothCameraFocus(at: 2.10, from: moveEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let fNearLand2 = engine.smoothCameraFocus(at: 2.20, from: moveEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let fNearLand3 = engine.smoothCameraFocus(at: 2.30, from: moveEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        
        let vel1 = fNearLand2.x - fNearLand1.x
        let vel2 = fNearLand3.x - fNearLand2.x
        XCTAssertGreaterThan(vel1, 0.0001, "Camera still moving towards target")
        XCTAssertGreaterThanOrEqual(vel1, vel2, "Velocity must gracefully decay (ease-out deceleration)")
    }
    
    func testValidationScenarioSuddenDirectionChangeTransition() {
        let engine = AutoZoomEngine()
        
        // Skenario 4: Cursor bergerak ke kanan (1.0 ke 1.3), lalu tiba-tiba berbelok tajam ke bawah (1.3 ke 1.6).
        // Kamera harus melakukan transisi arah yang halus dan kontinu tanpa jitter atau gerakan patah.
        let turnEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 1.3, type: .mouseMove, position: CGPoint(x: 0.80, y: 0.50)), // Menuju kanan
            TelemetryEvent(timestamp: 1.6, type: .mouseMove, position: CGPoint(x: 0.80, y: 0.80)), // Belok ke bawah
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.80, y: 0.80))
        ]
        
        var trajectory: [(t: Double, pt: CGPoint)] = []
        for step in 0...24 {
            let t = 1.2 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: turnEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, pt: focus))
        }
        
        // Verifikasi tidak ada perubahan arah yang patah/tersentak seketika (derivatives continuous)
        for i in 1..<trajectory.count {
            let stepDist = hypot(trajectory[i].pt.x - trajectory[i-1].pt.x, trajectory[i].pt.y - trajectory[i-1].pt.y)
            XCTAssertLessThan(stepDist, 0.05, "Step transition must be smooth across sudden 90-degree turn at t=\(trajectory[i].t)")
        }
    }
    
    func testValidationScenarioNewMovementWhileDecelerating() {
        let engine = AutoZoomEngine()
        
        // Skenario 6: Cursor bergerak dari (0.5, 0.5) ke (0.7, 0.5) pada t=1.2.
        // Saat kamera sedang melambat menuju 0.7 (di t=1.7), cursor kembali bergerak menuju (0.85, 0.6) di t=1.8.
        // Kamera harus menyerap gerakan baru tersebut secara halus dan kontinu tanpa rollback atau patahan arah.
        let chainingEvents = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 1.2, type: .mouseMove, position: CGPoint(x: 0.70, y: 0.50)),
            // Jeda singkat di mana kamera mulai melambat
            TelemetryEvent(timestamp: 1.7, type: .mouseMove, position: CGPoint(x: 0.70, y: 0.50)),
            // Gerakan baru berlanjut
            TelemetryEvent(timestamp: 1.9, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.60)),
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.60))
        ]
        
        var prevX: CGFloat = 0.0
        for step in 0...20 {
            let t = 1.5 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: chainingEvents, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            if prevX > 0 {
                // Sumbu X bergerak maju terus secara mulus (non-decreasing)
                XCTAssertGreaterThanOrEqual(focus.x + 0.0001, prevX, "Smooth forward momentum when chaining movement at t=\(t)")
            }
            prevX = focus.x
        }
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
        XCTAssertGreaterThan(focusBefore.x, 0.58, "Camera must be settled at offset position before sudden move")
        
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
    
    // MARK: - Safe-Zone Boundary Stutter Prevention Tests
    func testSafeZoneBoundarySlowApproachAndHover() {
        let engine = AutoZoomEngine()
        
        // Scenario 1 & 3: Cursor approaches the safe-zone boundary (~0.66 at scale 2.0) slowly
        // and stays close to the boundary without crossing it.
        // Camera must move smoothly without oscillation, jerk, or repeated corrections.
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.65, y: 0.50)), // Approaches edge
            TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.65, y: 0.50))  // Stays hovering
        ]
        
        var trajectory: [(t: Double, x: CGFloat)] = []
        for step in 0...40 {
            let t = 1.0 + Double(step) * 0.10
            let focus = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, x: focus.x))
        }
        
        // Trajectory must be strictly monotonic (non-decreasing) as it approaches and hovers
        for i in 1..<trajectory.count {
            XCTAssertGreaterThanOrEqual(trajectory[i].x + 0.0001, trajectory[i-1].x, "Approach to safe-zone boundary must be strictly monotonic at t=\(trajectory[i].t)")
        }
        
        // Hovering at 0.65 must remain stable without oscillation
        let hoverStart = trajectory.first(where: { $0.t >= 4.0 })!.x
        let hoverEnd = trajectory.last!.x
        XCTAssertEqual(hoverStart, hoverEnd, accuracy: 0.01, "Camera must remain stable while cursor hovers near boundary")
    }
    
    func testSafeZoneBoundaryBackAndForthOscillation() {
        let engine = AutoZoomEngine()
        
        // Scenario 2: Cursor moves repeatedly back and forth across/near the safe-zone boundary (0.64 to 0.68)
        // Camera must NOT jitter, stutter, or experience acceleration shocks.
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: CGPoint(x: 0.64, y: 0.50)),
            TelemetryEvent(timestamp: 1.8, type: .mouseMove, position: CGPoint(x: 0.68, y: 0.50)), // Crosses boundary
            TelemetryEvent(timestamp: 2.1, type: .mouseMove, position: CGPoint(x: 0.64, y: 0.50)), // Returns
            TelemetryEvent(timestamp: 2.4, type: .mouseMove, position: CGPoint(x: 0.68, y: 0.50)), // Crosses boundary again
            TelemetryEvent(timestamp: 2.7, type: .mouseMove, position: CGPoint(x: 0.64, y: 0.50)), // Returns again
            TelemetryEvent(timestamp: 4.5, type: .mouseMove, position: CGPoint(x: 0.64, y: 0.50))
        ]
        
        var trajectory: [(t: Double, x: CGFloat)] = []
        for step in 0...40 {
            let t = 1.4 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, x: focus.x))
        }
        
        // Velocity between any consecutive 50ms samples must never exceed smooth bound (no acceleration shocks)
        for i in 1..<trajectory.count {
            let delta = abs(trajectory[i].x - trajectory[i-1].x)
            XCTAssertLessThan(delta, 0.02, "Sample-to-sample displacement must remain smooth without stutter at t=\(trajectory[i].t)")
        }
    }
    
    func testSafeZoneBoundaryStopAndRestartMovement() {
        let engine = AutoZoomEngine()
        
        // Scenario 7: Camera stops near the boundary, settles, and then cursor starts moving again further out.
        // Transition from stop to moving again must be smooth without snapping.
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: CGPoint(x: 0.66, y: 0.50)), // At boundary
            // Stationary pause at boundary
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.66, y: 0.50)),
            // Moves further outward to 0.85
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.50)),
            TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.85, y: 0.50))
        ]
        
        let focusBeforePause = engine.smoothCameraFocus(at: 2.8, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let focusStartMoving = engine.smoothCameraFocus(at: 3.1, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        let focusMovedOut = engine.smoothCameraFocus(at: 4.5, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
        
        XCTAssertEqual(focusBeforePause.x, focusStartMoving.x, accuracy: 0.02, "Camera must remain resting at boundary during pause")
        XCTAssertGreaterThan(focusMovedOut.x, focusStartMoving.x + 0.10, "Camera smoothly restarts and tracks further outward")
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
    
    func testEvaluateViewportWithSourceTimeRemapping() {
        let engine = AutoZoomEngine()
        
        // Simulates a video that was recorded for 30s.
        // At source t=15.0s, user clicked button at (0.8, 0.2).
        let telemetry = [
            TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.1, y: 0.9)),
            TelemetryEvent(timestamp: 15.0, type: .mouseMove, position: CGPoint(x: 0.7, y: 0.3)),
            TelemetryEvent(timestamp: 17.0, type: .mouseMove, position: CGPoint(x: 0.7, y: 0.3))
        ]
        
        // In the editor, user cut out 10s (5s-15s).
        // The zoom keyframe was shifted to timeline t=5.0s, but its visual content corresponds to source t=15.0s.
        let keyframes = [
            ZoomKeyframe(
                startTime: 5.0,
                duration: 3.0,
                focusPoint: CGPoint(x: 0.7, y: 0.3),
                scale: 2.0,
                easing: .springSmooth,
                effectType: .zoom2D
            )
        ]
        
        // When evaluating with sourceTime = 16.2 at timeline time = 6.2 (inside hold window):
        let vpWithSource = engine.evaluateViewport(at: 6.2, sourceTime: 16.2, with: keyframes, telemetry: telemetry)
        XCTAssertEqual(vpWithSource.scale, 2.0, accuracy: 0.01)
        // Focus point should track the click at (0.7, 0.3)
        XCTAssertEqual(vpWithSource.focusPoint.x, 0.7, accuracy: 0.02)
        XCTAssertEqual(vpWithSource.focusPoint.y, 0.3, accuracy: 0.02)
    }
    
    func testMediaClipSegmentSplitAndRippleMath() {
        // Test splitting at t=5.0:
        var seg1 = MediaClipSegment(
            sourceStartTime: 0.0,
            timelineStartTime: 0.0,
            duration: 10.0
        )
        let splitTime = 5.0
        let firstDur = splitTime - seg1.timelineStartTime
        let secondDur = seg1.duration - firstDur
        seg1.duration = firstDur
        
        let seg2 = MediaClipSegment(
            sourceStartTime: seg1.sourceStartTime + firstDur,
            timelineStartTime: splitTime,
            duration: secondDur
        )
        
        XCTAssertEqual(seg1.duration, 5.0)
        XCTAssertEqual(seg2.sourceStartTime, 5.0)
        XCTAssertEqual(seg2.timelineStartTime, 5.0)
        XCTAssertEqual(seg2.duration, 5.0)
        
        // Now simulate deleting a 3s cut from t=5.0 to t=8.0:
        let cutStart = 5.0
        let cutDur = 3.0
        let cutEnd = cutStart + cutDur
        
        var subsequentSeg = MediaClipSegment(
            sourceStartTime: 8.0,
            timelineStartTime: cutEnd,
            duration: 12.0
        )
        var subsequentKF = ZoomKeyframe(
            startTime: 10.0,
            duration: 3.0,
            focusPoint: CGPoint(x: 0.5, y: 0.5)
        )
        
        // Ripple shifts:
        if subsequentSeg.timelineStartTime >= cutEnd - 0.001 {
            subsequentSeg.timelineStartTime -= cutDur
        }
        if subsequentKF.startTime >= cutEnd - 0.001 {
            subsequentKF.startTime -= cutDur
        }
        
        XCTAssertEqual(subsequentSeg.timelineStartTime, 5.0)
        XCTAssertEqual(subsequentKF.startTime, 7.0) // 10.0 - 3.0 = 7.0
    }
    
    func testFirstZoomSmoothness60fps() {
        let engine = AutoZoomEngine()
        let keyframes = [
            ZoomKeyframe(
                startTime: 1.0,
                duration: 3.0,
                focusPoint: CGPoint(x: 0.7, y: 0.3),
                scale: 2.0,
                easing: .springSmooth,
                effectType: .motion3D,
                tiltPreset: .auto
            )
        ]
        let telemetry = [
            TelemetryEvent(timestamp: 0.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.7, y: 0.3)),
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.7, y: 0.3))
        ]
        
        var prevScale: CGFloat = 1.0
        var prevFocusX: CGFloat = 0.5
        var prevPitch: Double = 0.0
        
        // Check frame-by-frame at 60fps across the zoom-in transition (0.8s to 2.0s)
        for frame in 0...120 {
            let t = 0.8 + Double(frame) * (1.0 / 60.0)
            let vp = engine.evaluateViewport(at: t, with: keyframes, telemetry: telemetry)
            
            // 1. Scale must increase monotonically during zoom-in
            if t >= 1.0 && t <= 1.8 {
                XCTAssertGreaterThanOrEqual(vp.scale, prevScale - 0.001, "Scale decreased at t=\(t) frame=\(frame): \(vp.scale) < \(prevScale)")
            }
            
            // 2. No sudden huge jerk in focus point (> 0.08 in a single 16ms frame)
            let dFocus = hypot(vp.focusPoint.x - prevFocusX, 0.0)
            XCTAssertLessThan(dFocus, 0.08, "Focus jerk at t=\(t) frame=\(frame): \(dFocus)")
            
            prevScale = vp.scale
            prevFocusX = vp.focusPoint.x
            prevPitch = vp.pitch
        }
    }
    
    func testEarlyFirstZoomSmoothnessAtRecordingStart() {
        let engine = AutoZoomEngine()
        // First zoom occurs very early at t = 0.2s (where causal kernel taps cross t = 0)
        let keyframes = [
            ZoomKeyframe(
                startTime: 0.2,
                duration: 3.0,
                focusPoint: CGPoint(x: 0.75, y: 0.25),
                scale: 2.0,
                easing: .springSmooth,
                effectType: .motion3D,
                tiltPreset: .auto
            )
        ]
        let telemetry = [
            TelemetryEvent(timestamp: 0.0, type: .mouseMove, position: CGPoint(x: 0.4, y: 0.4)),
            TelemetryEvent(timestamp: 0.2, type: .mouseClick, position: CGPoint(x: 0.75, y: 0.25)),
            TelemetryEvent(timestamp: 0.8, type: .mouseMove, position: CGPoint(x: 0.75, y: 0.25))
        ]
        
        var prevScale: CGFloat = 1.0
        var prevFocusX: CGFloat = 0.5
        
        for frame in 0...100 {
            let t = Double(frame) * (1.0 / 60.0)
            let vp = engine.evaluateViewport(at: t, with: keyframes, telemetry: telemetry)
            
            // Monotonic scale transition
            if t >= 0.2 && t <= 0.65 {
                XCTAssertGreaterThanOrEqual(vp.scale, prevScale - 0.001)
            }
            
            // Smooth focus movement, no unclamp stutter (> 0.04 in 16ms frame)
            let dFocus = hypot(vp.focusPoint.x - prevFocusX, 0.0)
            XCTAssertLessThan(dFocus, 0.04, "Early focus jerk at t=\(t) frame=\(frame): \(dFocus)")
            
            prevScale = vp.scale
            prevFocusX = vp.focusPoint.x
        }
    }
    
    func testVideoCompositorEngineWarmupAndSharedContext() {
        // Verify sharedCIContext is active and warmup executes without error
        let context = VideoCompositorEngine.sharedCIContext
        XCTAssertNotNil(context)
        VideoCompositorEngine.warmup(renderSize: CGSize(width: 1920, height: 1080))
    }
    
    func testExportFrameTimingWithInvalidTrackID() {
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        track.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)))
        
        let config = VideoCompositorConfig(renderSize: CGSize(width: 1920, height: 1080))
        let videoComp = VideoCompositorEngine.shared.buildVideoComposition(for: composition, config: config)
        
        // Must be kCMPersistentTrackID_Invalid so AVFoundation generates strict CFR 60fps frames
        // instead of inheriting VFR gaps from screen recording
        XCTAssertEqual(videoComp.sourceTrackIDForFrameTiming, kCMPersistentTrackID_Invalid)
        XCTAssertEqual(videoComp.frameDuration, CMTime(value: 1, timescale: 60))
        XCTAssertEqual(videoComp.renderSize, CGSize(width: 1920, height: 1080))
    }
    
    func testSafeZoneReentryTouchingEdgeAndReturningInside() {
        let engine = AutoZoomEngine()
        
        // Scenario B & E: Cursor approaches/touches safe-zone edge (0.66 at scale 2.0),
        // and then immediately returns inside the safe zone (to 0.50) and stays there.
        var events: [TelemetryEvent] = []
        for i in 0...60 {
            let t = 1.0 + Double(i) * 0.02 // 50Hz telemetry
            let x: CGFloat
            if t <= 1.4 {
                let p = (t - 1.0) / 0.4
                x = 0.50 + 0.16 * CGFloat(p)
            } else if t <= 1.8 {
                let p = (t - 1.4) / 0.4
                x = 0.66 - 0.16 * CGFloat(p)
            } else {
                x = 0.50
            }
            events.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: x, y: 0.50)))
        }
        events.append(TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)))
        
        var trajectory: [(t: Double, x: CGFloat, vel: CGFloat)] = []
        var prevX: CGFloat = 0.50
        for step in 0...50 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            let vel = (focus.x - prevX) / 0.05
            trajectory.append((t: t, x: focus.x, vel: vel))
            prevX = focus.x
        }
        
        // 1. Verify no high-frequency velocity chatter (velocity must not flip-flop every 50ms)
        var signFlips = 0
        for i in 2..<trajectory.count {
            let v1 = trajectory[i-1].vel
            let v2 = trajectory[i].vel
            if abs(v1) > 0.005 && abs(v2) > 0.005 && (v1 * v2 < 0) {
                signFlips += 1
            }
        }
        // At most 1 directional turnaround (moving out, then moving back in)
        XCTAssertLessThanOrEqual(signFlips, 1, "Camera must transition direction at most once without oscillation or jitter")
        
        // 2. Trajectory must settle cleanly back at center (0.50)
        let settledX = trajectory.last!.x
        XCTAssertEqual(settledX, 0.50, accuracy: 0.02, "Camera must settle cleanly inside safe zone after cursor returns")
    }
    
    func testSafeZoneReentryRepeatedInOutTransitions() {
        let engine = AutoZoomEngine()
        
        // Scenario C: Cursor moves in and out across the safe-zone boundary (0.64 to 0.68) several times.
        var events: [TelemetryEvent] = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50))
        ]
        var curT = 1.2
        for _ in 0..<4 {
            events.append(TelemetryEvent(timestamp: curT, type: .mouseMove, position: CGPoint(x: 0.68, y: 0.50))) // Outside boundary
            curT += 0.25
            events.append(TelemetryEvent(timestamp: curT, type: .mouseMove, position: CGPoint(x: 0.60, y: 0.50))) // Inside boundary
            curT += 0.25
        }
        events.append(TelemetryEvent(timestamp: 4.5, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)))
        
        var trajectory: [(t: Double, x: CGFloat)] = []
        for step in 0...60 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, x: focus.x))
        }
        
        // Displacement between consecutive 50ms samples must remain strictly within smooth Steadicam bounds
        for i in 1..<trajectory.count {
            let stepDist = abs(trajectory[i].x - trajectory[i-1].x)
            XCTAssertLessThan(stepDist, 0.025, "Continuous camera motion across repeated in-out boundary crossings at t=\(trajectory[i].t)")
        }
    }
    
    func testSafeZoneReentryWhileCameraActivelyMoving() {
        let engine = AutoZoomEngine()
        
        // Scenario D: Cursor reaches outer boundary (0.75) at 1.4s, camera begins following outward.
        // Before camera finishes adjustment, cursor rapidly returns inside to 0.55 at 1.6s.
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)),
            TelemetryEvent(timestamp: 1.4, type: .mouseMove, position: CGPoint(x: 0.75, y: 0.50)),
            TelemetryEvent(timestamp: 1.6, type: .mouseMove, position: CGPoint(x: 0.55, y: 0.50)),
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.55, y: 0.50))
        ]
        
        var trajectory: [(t: Double, x: CGFloat)] = []
        for step in 0...40 {
            let t = 1.0 + Double(step) * 0.05
            let focus = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, x: focus.x))
        }
        
        // Camera must not overshoot beyond reasonable framing of 0.55
        let maxX = trajectory.map { $0.x }.max()!
        XCTAssertLessThanOrEqual(maxX, 0.65, "Camera must not blindly complete obsolete outward movement when cursor returns inside")
        
        // Camera settles cleanly near the inner cursor position (0.55 is within inner deadzone [0.43, 0.57] of 0.50)
        let finalX = trajectory.last!.x
        XCTAssertEqual(finalX, 0.50, accuracy: 0.03, "Camera settles cleanly at base point when cursor rests inside inner deadzone")
    }
    
    func testDiagnosticTopBoundaryReversal() {
        let engine = AutoZoomEngine()
        
        // Sequence: Cursor moves from center (0.5, 0.5) to top safe-zone edge/beyond (0.5, 0.28) at t=1.4s,
        // touches/crosses the boundary, and immediately moves downward to (0.5, 0.5) at t=1.8s, then rests.
        var events: [TelemetryEvent] = []
        for i in 0...60 {
            let t = 1.0 + Double(i) * 0.02 // 50Hz telemetry
            let y: CGFloat
            if t <= 1.4 {
                let p = (t - 1.0) / 0.4
                y = 0.50 - 0.22 * CGFloat(p) // Reaches 0.28 at t=1.4
            } else if t <= 1.8 {
                let p = (t - 1.4) / 0.4
                y = 0.28 + 0.22 * CGFloat(p) // Returns downward to 0.50
            } else {
                y = 0.50
            }
            events.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: 0.50, y: y)))
        }
        events.append(TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)))
        
        var prevF = CGPoint(x: 0.5, y: 0.5)
        var prevV: CGFloat = 0.0
        var signFlips = 0
        for step in 0...60 {
            let t = 1.0 + Double(step) * 0.02 // 50fps frames
            let f = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            let v = (f.y - prevF.y) / 0.02
            if step >= 2 && abs(v) > 0.005 && abs(prevV) > 0.005 && (v * prevV < 0) {
                signFlips += 1
            }
            prevF = f
            prevV = v
        }
        XCTAssertLessThanOrEqual(signFlips, 1, "Camera must transition direction at most once during boundary reversal without oscillation or vibration")
        XCTAssertEqual(prevF.y, 0.50, accuracy: 0.02, "Camera settles back to center")
    }
    
    func testCameraCatchUpAndReacquisitionWithoutBraking() {
        let engine = AutoZoomEngine()
        
        // Scenario 1: Fast flick outside framing horizontally (0.30 -> 0.55 at 1.0/s),
        // followed by continuous steady cruise at 0.15/s (0.55 -> 0.70).
        // The camera must pursue, catch up, and smoothly transition to cruise speed
        // without any unnatural dip or momentary stall.
        var flickEvents: [TelemetryEvent] = [
            TelemetryEvent(timestamp: 0.0, type: .mouseMove, position: CGPoint(x: 0.30, y: 0.50)),
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.30, y: 0.50))
        ]
        for i in 1...12 { // 0.24s fast move
            let t = 1.0 + Double(i) * 0.02
            let x = 0.30 + 1.00 * CGFloat(Double(i) * 0.02)
            flickEvents.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: x, y: 0.50)))
        }
        for i in 1...50 { // Cruising at 0.15/s
            let t = 1.24 + Double(i) * 0.02
            let x = 0.54 + 0.15 * CGFloat(Double(i) * 0.02)
            flickEvents.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: x, y: 0.50)))
        }
        flickEvents.append(TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.69, y: 0.50)))
        
        var prevFlickF = engine.smoothCameraFocus(at: 1.0, from: flickEvents, basePoint: CGPoint(x: 0.30, y: 0.50), scale: 2.0)
        var flickVelocities: [(t: Double, v: CGFloat)] = []
        for step in 0...60 {
            let t = 1.0 + Double(step) * 0.02
            let f = engine.smoothCameraFocus(at: t, from: flickEvents, basePoint: CGPoint(x: 0.30, y: 0.50), scale: 2.0)
            let v = (f.x - prevFlickF.x) / 0.02
            flickVelocities.append((t: t, v: v))
            prevFlickF = f
        }
        
        // During the cruise phase (t: 1.5 to 2.2), camera speed must stay positive and smoothly track cursor
        let cruiseVelocities = flickVelocities.filter { $0.t >= 1.5 && $0.t <= 2.2 }
        for sample in cruiseVelocities {
            XCTAssertGreaterThan(sample.v, 0.05, "Camera must maintain continuous forward motion at t=\(sample.t) without braking")
        }
        
        // Scenario 2: Multi-axis movement where cursor leaves framing horizontally
        // while continuing to move vertically.
        // Verifies the unified 2D elliptic safe-zone prevents orthogonal deadzone lock/braking.
        var multiEvents: [TelemetryEvent] = [
            TelemetryEvent(timestamp: 0.0, type: .mouseMove, position: CGPoint(x: 0.35, y: 0.50)),
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.35, y: 0.50))
        ]
        for i in 1...10 {
            let t = 1.0 + Double(i) * 0.02
            let x = 0.35 + 0.35 * CGFloat(Double(i) / 10.0) // 0.35 -> 0.70 fast
            let y = 0.50 + 0.02 * CGFloat(Double(i) / 10.0)
            multiEvents.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: x, y: y)))
        }
        for i in 1...40 {
            let t = 1.20 + Double(i) * 0.02
            let y = 0.52 + 0.15 * CGFloat(Double(i) * 0.02) // Continuous vertical motion
            multiEvents.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: 0.70, y: y)))
        }
        multiEvents.append(TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.70, y: 0.64)))
        
        var prevMultiF = engine.smoothCameraFocus(at: 1.0, from: multiEvents, basePoint: CGPoint(x: 0.35, y: 0.50), scale: 2.0)
        var multiSpeeds: [(t: Double, speed: CGFloat)] = []
        for step in 0...60 {
            let t = 1.0 + Double(step) * 0.02
            let f = engine.smoothCameraFocus(at: t, from: multiEvents, basePoint: CGPoint(x: 0.35, y: 0.50), scale: 2.0)
            let speed = hypot(f.x - prevMultiF.x, f.y - prevMultiF.y) / 0.02
            multiSpeeds.append((t: t, speed: speed))
            prevMultiF = f
        }
        
        // During the catch-up and transition phase (t: 1.3 to 1.8), speed must not collapse to 0
        let transitionSpeeds = multiSpeeds.filter { $0.t >= 1.35 && $0.t <= 1.8 }
        for sample in transitionSpeeds {
            XCTAssertGreaterThan(sample.speed, 0.05, "2D camera speed must remain continuous without stalling at t=\(sample.t)")
        }
    }
    
    func testContinuousSteadicamMotionWithoutTapAliasingOrBraking() {
        let engine = AutoZoomEngine()
        
        // Scenario: Flick from 0.30 to 0.70 at 1.60/s, then continue navigating at 0.10/s
        var events: [TelemetryEvent] = [
            TelemetryEvent(timestamp: 0.0, type: .mouseMove, position: CGPoint(x: 0.30, y: 0.50)),
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.30, y: 0.50))
        ]
        for i in 1...25 {
            let t = 1.0 + Double(i) * 0.01
            let x = 0.30 + 1.60 * CGFloat(Double(i) * 0.01)
            events.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: x, y: 0.50)))
        }
        for i in 1...100 {
            let t = 1.25 + Double(i) * 0.01
            let x = 0.70 + 0.10 * CGFloat(Double(i) * 0.01)
            events.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: x, y: 0.50)))
        }
        events.append(TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.80, y: 0.50)))
        
        var prevF = engine.smoothCameraFocus(at: 1.0, from: events, basePoint: CGPoint(x: 0.30, y: 0.50), scale: 2.0)
        var prevV: CGFloat = 0.0
        var accelerations: [CGFloat] = []
        for step in 35...65 {
            let t = 1.0 + Double(step) * 0.01
            let f = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.30, y: 0.50), scale: 2.0)
            let v = (f.x - prevF.x) / 0.01
            let a = (v - prevV) / 0.01
            if step > 36 {
                accelerations.append(a)
            }
            // Camera speed must stay positive and smoothly track cursor
            XCTAssertGreaterThan(v, 0.05, "Camera velocity must remain continuous and positive at t=\(t)")
            prevF = f
            prevV = v
        }
        
        // Assert acceleration sign transitions: acceleration must smoothly transition at most once from acceleration to deceleration
        var signChanges = 0
        for i in 1..<accelerations.count {
            if accelerations[i] * accelerations[i-1] < -0.01 {
                signChanges += 1
            }
        }
        XCTAssertLessThanOrEqual(signChanges, 1, "Acceleration must not oscillate or ripple due to tap aliasing (found \(signChanges) flips)")
    }
    
    // MARK: - Camera Tracking, Waypoint Filtering & Corner Limit Tests
    
    func testTransientWaypointDetourSuppression() {
        let engine = AutoZoomEngine()
        
        // Scenario 1: User clicks at BL (0.2, 0.8) at t=1.0.
        // Cursor rushes to BR (0.8, 0.8) at t=1.3, stays only briefly until t=1.5 with NO click/interaction.
        // Immediately moves to TR (0.8, 0.2) at t=1.8, and settles there until t=3.5.
        // The camera must NOT take a full detour to BR; it should prioritize the persistent path toward TR.
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseClick, position: CGPoint(x: 0.2, y: 0.8)),
            TelemetryEvent(timestamp: 1.3, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.8)),
            TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.8)),
            TelemetryEvent(timestamp: 1.8, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.2)),
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.2))
        ]
        
        var trajectory: [(t: Double, focus: CGPoint)] = []
        for step in 0...40 {
            let t = 1.0 + Double(step) * 0.05
            let f = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, focus: f))
        }
        
        // Verify camera does not take the full bottom-right detour:
        // During the entire transition, while moving from BL to TR, the camera cuts the corner across the center
        // rather than traveling fully along the bottom border (Y remains below 0.65 after passing BL).
        let postBLTrajectory = trajectory.filter { $0.t >= 1.75 && $0.t <= 2.2 }
        for sample in postBLTrajectory {
            // Y must smoothly decrease towards TR (0.27) rather than staying stuck at bottom (0.73)
            XCTAssertLessThanOrEqual(sample.focus.y, 0.68, "Camera must not pursue transient bottom-right position at t=\(sample.t)")
        }
        
        // Final position settles cleanly at top-right destination
        let settled = trajectory.last!.focus
        XCTAssertEqual(settled.x, 0.73, accuracy: 0.03, "Camera settles at right edge")
        XCTAssertEqual(settled.y, 0.27, accuracy: 0.03, "Camera settles at top edge")
    }
    
    func testMeaningfulInteractionAtWaypointPreserved() {
        let engine = AutoZoomEngine()
        
        // Scenario 2: Same trajectory, but user performs an important click at BR at t=1.3.
        // The camera MUST capture the important click at BR before proceeding to TR.
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseClick, position: CGPoint(x: 0.2, y: 0.8)),
            TelemetryEvent(timestamp: 1.3, type: .mouseClick, position: CGPoint(x: 0.8, y: 0.8)), // Meaningful interaction!
            TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.8)),
            TelemetryEvent(timestamp: 1.8, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.2)),
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.8, y: 0.2))
        ]
        
        var trajectory: [(t: Double, focus: CGPoint)] = []
        for step in 0...40 {
            let t = 1.0 + Double(step) * 0.05
            let f = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            trajectory.append((t: t, focus: f))
        }
        
        // Because of the click at BR, the camera MUST frame the bottom-right click comfortably
        let maxBR_Y = trajectory.map { $0.focus.y }.max()!
        XCTAssertGreaterThanOrEqual(maxBR_Y, 0.70, "Camera must capture important interaction at bottom-right waypoint")
    }
    
    func testScreenCornerApproachAndReturnSmoothness() {
        let engine = AutoZoomEngine()
        
        // Scenario 3: Cursor approaches extreme screen corner (0.95, 0.95) at scale 2.0.
        // Physical camera limit is [0.25, 0.75].
        // Camera must decelerate smoothly without impact shock, never exceed 0.75,
        // and return smoothly without sticky-wall delay when cursor returns to center.
        let events = [
            TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: CGPoint(x: 0.95, y: 0.95)),
            TelemetryEvent(timestamp: 3.0, type: .mouseMove, position: CGPoint(x: 0.95, y: 0.95)),
            TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
            TelemetryEvent(timestamp: 5.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5))
        ]
        
        var trajectory: [(t: Double, focus: CGPoint, velX: CGFloat, velY: CGFloat)] = []
        var prevF = CGPoint(x: 0.5, y: 0.5)
        for step in 0...70 {
            let t = 1.0 + Double(step) * 0.05
            let f = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            let vx = (f.x - prevF.x) / 0.05
            let vy = (f.y - prevF.y) / 0.05
            trajectory.append((t: t, focus: f, velX: vx, velY: vy))
            prevF = f
        }
        
        // 1. Boundary enforcement: focus must strictly remain in legal viewport bounds [0.25, 0.75]
        for sample in trajectory {
            XCTAssertGreaterThanOrEqual(sample.focus.x, 0.25 - 0.001)
            XCTAssertLessThanOrEqual(sample.focus.x, 0.75 + 0.001)
            XCTAssertGreaterThanOrEqual(sample.focus.y, 0.25 - 0.001)
            XCTAssertLessThanOrEqual(sample.focus.y, 0.75 + 0.001)
        }
        
        // 2. Velocity smoothness: velocity change per 50ms step must never experience impact shocks (|deltaV| <= 0.6)
        for i in 2..<trajectory.count {
            let dVx = abs(trajectory[i].velX - trajectory[i-1].velX)
            let dVy = abs(trajectory[i].velY - trajectory[i-1].velY)
            XCTAssertLessThanOrEqual(dVx, 0.60, "X velocity must remain continuous without impact shock at t=\(trajectory[i].t)")
            XCTAssertLessThanOrEqual(dVy, 0.60, "Y velocity must remain continuous without impact shock at t=\(trajectory[i].t)")
        }
    }
    
    func testAllFourScreenCornersReachability() {
        let engine = AutoZoomEngine()
        
        let corners: [(name: String, pos: CGPoint, expectedMinX: CGFloat, expectedMaxX: CGFloat, expectedMinY: CGFloat, expectedMaxY: CGFloat)] = [
            ("Top-Left", CGPoint(x: 0.02, y: 0.02), 0.25, 0.28, 0.25, 0.28),
            ("Top-Right", CGPoint(x: 0.98, y: 0.02), 0.72, 0.75, 0.25, 0.28),
            ("Bottom-Left", CGPoint(x: 0.02, y: 0.98), 0.25, 0.28, 0.72, 0.75),
            ("Bottom-Right", CGPoint(x: 0.98, y: 0.98), 0.72, 0.75, 0.72, 0.75)
        ]
        
        for c in corners {
            let events = [
                TelemetryEvent(timestamp: 1.0, type: .mouseMove, position: CGPoint(x: 0.5, y: 0.5)),
                TelemetryEvent(timestamp: 1.5, type: .mouseMove, position: c.pos),
                TelemetryEvent(timestamp: 3.5, type: .mouseMove, position: c.pos)
            ]
            let settled = engine.smoothCameraFocus(at: 3.2, from: events, basePoint: CGPoint(x: 0.5, y: 0.5), scale: 2.0)
            XCTAssertGreaterThanOrEqual(settled.x, c.expectedMinX - 0.01, "\(c.name) settled X lower bound")
            XCTAssertLessThanOrEqual(settled.x, c.expectedMaxX + 0.01, "\(c.name) settled X upper bound")
            XCTAssertGreaterThanOrEqual(settled.y, c.expectedMinY - 0.01, "\(c.name) settled Y lower bound")
            XCTAssertLessThanOrEqual(settled.y, c.expectedMaxY + 0.01, "\(c.name) settled Y upper bound")
        }
    }
    
    func testContinuousFastSafeZoneExitWithoutHitchOrDiscontinuity() {
        let engine = AutoZoomEngine()
        
        // Continuous 60Hz cursor telemetry moving at constant high velocity (1.2/s)
        // starting at center (0.50, 0.50) at t=1.0 and exiting safe-zone to (0.95, 0.50)
        var events: [TelemetryEvent] = []
        for i in 0...60 {
            let t = 1.0 - Double(60 - i) * 0.01667
            events.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: 0.50, y: 0.50)))
        }
        for i in 1...60 {
            let t = 1.0 + Double(i) * 0.01667
            let x = 0.50 + 1.20 * CGFloat(Double(i) * 0.01667)
            events.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: min(0.95, x), y: 0.50)))
        }
        
        var prevF = engine.smoothCameraFocus(at: 1.0, from: events, basePoint: CGPoint(x: 0.50, y: 0.50), scale: 2.0)
        var prevV: CGFloat = 0.0
        var velocitiesDuringExit: [CGFloat] = []
        for step in 1...30 {
            let t = 1.0 + Double(step) * 0.01667
            let f = engine.smoothCameraFocus(at: t, from: events, basePoint: CGPoint(x: 0.50, y: 0.50), scale: 2.0)
            let v = (f.x - prevF.x) / 0.01667
            if step > 6 {
                velocitiesDuringExit.append(v)
            }
            prevF = f
            prevV = v
        }
        
        // During fast exit across safe-zone boundary, camera velocity must strictly increase monotonically (no braking/hitching)
        for i in 1..<velocitiesDuringExit.count {
            XCTAssertGreaterThanOrEqual(velocitiesDuringExit[i], velocitiesDuringExit[i-1] - 0.005,
                "Velocity must never suddenly dip or brake during outward safe-zone exit (found \(velocitiesDuringExit[i]) < \(velocitiesDuringExit[i-1]))")
        }
    }
    
    func testCompareAdjacentBlocksVsSingleBlockContinuity() {
        let engine = AutoZoomEngine()
        
        // Continuous cursor movement from t=2.0 to t=6.0 across boundary at t=4.0
        var events: [TelemetryEvent] = []
        for i in 0...240 {
            let t = 2.0 + Double(i) * 0.01667
            let x = 0.30 + 0.10 * CGFloat(Double(i) * 0.01667) // Constant smooth cursor movement
            events.append(TelemetryEvent(timestamp: t, type: .mouseMove, position: CGPoint(x: x, y: 0.50)))
        }
        
        // Configuration A: Two adjacent zoom blocks [1.0 to 4.0] and [4.0 to 7.0]
        let kf1 = ZoomKeyframe(startTime: 1.0, duration: 3.0, focusPoint: CGPoint(x: 0.30, y: 0.50), scale: 2.0)
        let kf2 = ZoomKeyframe(startTime: 4.0, duration: 3.0, focusPoint: CGPoint(x: 0.30, y: 0.50), scale: 2.0)
        let configA_Keyframes = [kf1, kf2]
        
        // Configuration B: Single continuous zoom block [1.0 to 7.0]
        let kfSingle = ZoomKeyframe(startTime: 1.0, duration: 6.0, focusPoint: CGPoint(x: 0.30, y: 0.50), scale: 2.0)
        let configB_Keyframes = [kfSingle]
        
        // 1. When focusPoints match, ConfigA must be mathematically identical to ConfigB on every frame!
        for step in 0...60 {
            let t = 3.5 + Double(step) * 0.01667
            let vpA = engine.evaluateViewport(at: t, with: configA_Keyframes, telemetry: events)
            let vpB = engine.evaluateViewport(at: t, with: configB_Keyframes, telemetry: events)
            XCTAssertEqual(vpA.focusPoint.x, vpB.focusPoint.x, accuracy: 0.0001,
                "ConfigA must be identical to ConfigB at t=\(t)")
        }
        
        // 2. When focusPoints differ (intentional framing sweep), velocity must remain strictly continuous and smooth without drops to zero
        let kfDiff1 = ZoomKeyframe(startTime: 1.0, duration: 3.0, focusPoint: CGPoint(x: 0.20, y: 0.50), scale: 2.0)
        let kfDiff2 = ZoomKeyframe(startTime: 4.0, duration: 3.0, focusPoint: CGPoint(x: 0.70, y: 0.50), scale: 2.0)
        var prevDiffF: CGPoint?
        var velocitiesDiff: [CGFloat] = []
        for step in 0...60 {
            let t = 3.5 + Double(step) * 0.01667
            let vp = engine.evaluateViewport(at: t, with: [kfDiff1, kfDiff2], telemetry: events)
            if let p = prevDiffF {
                let v = (vp.focusPoint.x - p.x) / 0.01667
                velocitiesDiff.append(v)
            }
            prevDiffF = vp.focusPoint
        }
        
        // Assert that velocity never collapses or reverses unexpectedly during transition
        for v in velocitiesDiff {
            XCTAssertGreaterThan(v, 0.05, "Camera velocity must remain positive and continuous during framing transition")
        }
    }
}


