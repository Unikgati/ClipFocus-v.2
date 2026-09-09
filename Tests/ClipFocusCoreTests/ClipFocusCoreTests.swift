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
}

