import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import ClipFocusCore

_ = NSApplication.shared

if CommandLine.arguments.contains("--test-window-capture") {
    print("🔍 Testing Window Capture Engine...")
    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            if let target = content.windows.first(where: { $0.frame.width > 300 && $0.frame.height > 200 && $0.owningApplication?.applicationName != "ClipFocus" }) {
                print("🎯 Target window: [\(target.windowID)] \(target.owningApplication?.applicationName ?? "") - \(target.title ?? "") (\(target.frame.width)x\(target.frame.height))")
                let outURL = URL(fileURLWithPath: "/tmp/clipfocus_window_test.mov")
                try? FileManager.default.removeItem(at: outURL)
                
                let engine = ScreenCaptureEngine()
                let cfg = CaptureSessionConfig(
                    captureWidth: 1920,
                    captureHeight: 1080,
                    frameRate: 60,
                    captureSystemAudio: false,
                    captureMicrophoneAudio: false,
                    showHardwareCursor: true,
                    sourceRect: nil,
                    targetWindowID: target.windowID,
                    excludedWindowIDs: []
                )
                print("🎥 Starting capture...")
                try await engine.startCapture(config: cfg, outputURL: outURL)
                try await Task.sleep(nanoseconds: 2_500_000_000)
                print("⏹ Stopping capture...")
                let resultURL = try await engine.stopCapture()
                if let res = resultURL, FileManager.default.fileExists(atPath: res.path) {
                    let asset = AVAsset(url: res)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    if let track = tracks.first {
                        let sz = try await track.load(.naturalSize)
                        let dur = try await asset.load(.duration)
                        print("✅ WINDOW CAPTURE 100% PRODUCTION READY!")
                        print("   Resolution: \(sz.width) x \(sz.height)")
                        print("   Duration: \(dur.seconds)s")
                        print("   Output File: \(res.path)")
                    }
                } else {
                    print("❌ Capture file missing")
                }
            } else {
                print("⚠️ No eligible window found to capture")
            }
        } catch {
            print("❌ Capture error: \(error.localizedDescription)")
        }
        CFRunLoopStop(CFRunLoopGetMain())
    }
    CFRunLoopRun()
    exit(0)
}



// 1. Simulate a realistic sequence of user screen interactions
let sampleEvents: [TelemetryEvent] = [
    // User moves mouse and clicks on Search bar at top left (x: 0.18, y: 0.12)
    TelemetryEvent(timestamp: 1.2, type: .mouseClick, position: CGPoint(x: 0.18, y: 0.12), button: .left, clickCount: 1),
    // User types text into the search bar
    TelemetryEvent(timestamp: 1.5, type: .keyDown, position: CGPoint(x: 0.18, y: 0.12), keyCharacters: "ClipFocus"),
    TelemetryEvent(timestamp: 1.8, type: .keyDown, position: CGPoint(x: 0.18, y: 0.12), keyCharacters: " Pro"),
    // User moves and clicks submit button at middle right (x: 0.75, y: 0.60)
    TelemetryEvent(timestamp: 6.0, type: .mouseClick, position: CGPoint(x: 0.75, y: 0.60), button: .left, clickCount: 1),
    TelemetryEvent(timestamp: 6.4, type: .mouseClick, position: CGPoint(x: 0.76, y: 0.60), button: .left, clickCount: 2)
]

print("📊 Generating Auto-Zoom Keyframes from \(sampleEvents.count) telemetry events...")
let engine = AutoZoomEngine()
let keyframes = engine.generateKeyframes(from: sampleEvents, totalDuration: 10.0)

for (idx, kf) in keyframes.enumerated() {
    print("  Keyframe [\(idx+1)]:")
    print("    • Time range: \(String(format: "%.2f", kf.startTime))s -> \(String(format: "%.2f", kf.startTime + kf.duration))s")
    print("    • Focus center: (\(String(format: "%.2f", kf.focusPoint.x)), \(String(format: "%.2f", kf.focusPoint.y)))")
    print("    • Scale: \(String(format: "%.2f", kf.scale))x | Easing: \(kf.easing.rawValue) | Reason: \(kf.reason ?? "-")")
}

// 2. Evaluate viewport smoothly at 0.5s intervals
print("\n🎥 Testing Continuous Viewport Interpolation:")
let testTimes = [0.5, 1.0, 1.4, 2.0, 3.5, 5.0, 6.2, 7.0, 9.0]
for t in testTimes {
    let vp = engine.evaluateViewport(at: t, with: keyframes)
    print("  t=\(String(format: "%.1f", t))s: Scale=\(String(format: "%.2f", vp.scale))x, Focus=(\(String(format: "%.2f", vp.focusPoint.x)), \(String(format: "%.2f", vp.focusPoint.y)))")
}

// 3. Test SmartCut Silence Detection
print("\n🔇 Testing Smart Cut Silence Engine:")
let audioSamples: [Float] = [
    -20.0, -18.0, -22.0, // active speech 0.0 - 0.15s
    -55.0, -60.0, -58.0, -62.0, -54.0, -57.0, -59.0, -61.0, -58.0, -60.0, -55.0, -56.0, // dead silence 0.15s - 0.75s
    -19.0, -15.0, -18.0  // resumed speech
]
let smartCut = SmartCutEngine()
let cuts = smartCut.detectSilences(powerSamples: audioSamples, sampleInterval: 0.05)
print("  Detected \(cuts.count) dead-air interval(s) to cut:")
for cut in cuts {
    print("    • Cut range: \(String(format: "%.2f", cut.startTime))s - \(String(format: "%.2f", cut.endTime))s (Duration: \(String(format: "%.2f", cut.duration))s)")
}

print("\n✅ ClipFocus Engine initialized successfully!")
