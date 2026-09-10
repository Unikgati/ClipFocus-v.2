import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit

/// Manager orchestrating real screen capture, cursor telemetry, permissions, and recording state
@Observable
public final class CaptureManager: @unchecked Sendable {
    public static let shared = CaptureManager()
    
    public private(set) var isRecording: Bool = false
    public private(set) var isPaused: Bool = false
    public private(set) var recordingDuration: TimeInterval = 0.0
    public private(set) var hasScreenCapturePermission: Bool = false
    public private(set) var currentOutputFileURL: URL?
    public private(set) var lastRecordedProject: ClipFocusProject?
    public private(set) var lastErrorMessage: String?
    
    private let captureEngine = ScreenCaptureEngine()
    private let cursorTracker = CursorTracker()
    private let autoZoomEngine = AutoZoomEngine()
    private var durationTimer: Timer?
    private var accumulatedDuration: TimeInterval = 0.0
    private var lastResumeTime: Date?
    private var pauseDate: Date?
    
    public var captureHardwareCursor: Bool = false
    
    public init() {
        checkPermissions()
    }
    
    /// Check current macOS screen capture permission
    public func checkPermissions() {
        let hasAccess = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async {
            self.hasScreenCapturePermission = hasAccess
        }
    }
    
    /// Prompt the macOS system permission dialog
    public func requestPermissions() {
        let requested = CGRequestScreenCaptureAccess()
        DispatchQueue.main.async {
            self.hasScreenCapturePermission = requested
        }
    }
    
    /// Open macOS System Settings directly to Privacy & Security -> Screen Recording
    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Start a REAL screen recording session using ScreenCaptureKit and CursorTracker
    public func startRecording(
        mode: String = "Full Screen",
        captureMicrophoneAudio: Bool = true,
        captureSystemAudio: Bool = true,
        targetMicrophoneName: String? = nil,
        sourceRect: CGRect? = nil,
        targetWindowID: CGWindowID? = nil,
        excludedWindowIDs: [CGWindowID] = []
    ) async throws {
        checkPermissions()
        
        guard CGPreflightScreenCaptureAccess() else {
            requestPermissions()
            throw NSError(
                domain: "ClipFocus",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission not granted. Please enable ClipFocus in System Settings > Privacy & Security > Screen Recording."]
            )
        }
        
        // Prepare output file path in ~/Movies/ClipFocus/
        let fileManager = FileManager.default
        let moviesDir = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let outputDir = moviesDir.appendingPathComponent("ClipFocus", isDirectory: true)
        if !fileManager.fileExists(atPath: outputDir.path) {
            try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestampStr = formatter.string(from: Date())
        let videoURL = outputDir.appendingPathComponent("ClipFocus_\(timestampStr).mov")
        
        // Find primary display resolution
        let primaryScreen = NSScreen.screens.first
        let screenWidth = Int(primaryScreen?.frame.width ?? 1920) * 2 // Retina scale
        let screenHeight = Int(primaryScreen?.frame.height ?? 1080) * 2
        
        let config = CaptureSessionConfig(
            captureWidth: screenWidth > 0 ? screenWidth : 1920,
            captureHeight: screenHeight > 0 ? screenHeight : 1080,
            frameRate: 60,
            captureSystemAudio: captureSystemAudio,
            captureMicrophoneAudio: captureMicrophoneAudio,
            targetMicrophoneName: targetMicrophoneName,
            showHardwareCursor: captureHardwareCursor, // Screen Studio / FocuSee style: clean video stream for vector cursor overlay
            sourceRect: sourceRect,
            targetWindowID: targetWindowID,
            excludedWindowIDs: excludedWindowIDs
        )
        
        // Start engine and cursor tracker
        try await captureEngine.startCapture(config: config, outputURL: videoURL)
        cursorTracker.startTracking()
        
        await MainActor.run {
            self.currentOutputFileURL = videoURL
            self.isRecording = true
            self.isPaused = false
            self.accumulatedDuration = 0.0
            self.recordingDuration = 0.0
            self.lastResumeTime = Date()
            self.pauseDate = nil
            self.lastErrorMessage = nil
            
            // Duration ticker
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, self.isRecording, !self.isPaused, let resume = self.lastResumeTime else { return }
                self.recordingDuration = self.accumulatedDuration + Date().timeIntervalSince(resume)
            }
        }
    }
    
    /// Pause current recording session
    public func pauseRecording() {
        guard isRecording, !isPaused, let resume = lastResumeTime else { return }
        accumulatedDuration += Date().timeIntervalSince(resume)
        isPaused = true
        pauseDate = Date()
        captureEngine.pauseCapture()
        cursorTracker.pauseTracking()
    }
    
    /// Resume paused recording session
    public func resumeRecording() {
        guard isRecording, isPaused, let pause = pauseDate else { return }
        let pausedDuration = Date().timeIntervalSince(pause)
        lastResumeTime = Date()
        pauseDate = nil
        isPaused = false
        captureEngine.resumeCapture(pausedDuration: pausedDuration)
        cursorTracker.resumeTracking(pausedDuration: pausedDuration)
    }
    
    /// Discard current recording, delete output file, and reset
    public func discardRecording() async throws {
        durationTimer?.invalidate()
        durationTimer = nil
        _ = cursorTracker.stopTracking()
        await captureEngine.cancelCapture()
        if let url = currentOutputFileURL {
            try? FileManager.default.removeItem(at: url)
            let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
            try? FileManager.default.removeItem(at: jsonURL)
        }
        await MainActor.run {
            self.isRecording = false
            self.isPaused = false
            self.recordingDuration = 0.0
            self.currentOutputFileURL = nil
        }
    }
    
    /// Stop current recording, finalize movie, analyze telemetry, and construct project
    public func stopRecording(
        preferredEffectType: ZoomEffectType = .zoom2D,
        autoZoomOnTyping: Bool = true
    ) async throws -> (URL, ClipFocusProject) {
        durationTimer?.invalidate()
        durationTimer = nil
        
        let rawEvents = cursorTracker.stopTracking()
        guard let finalVideoURL = try await captureEngine.stopCapture(),
              FileManager.default.fileExists(atPath: finalVideoURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: finalVideoURL.path),
              (attrs[.size] as? Int64 ?? 0) > 1024 else {
            throw NSError(domain: "ClipFocus", code: 500, userInfo: [NSLocalizedDescriptionKey: "Recording was stopped before frames could be encoded (file is empty). Please record for at least 1-2 seconds."])
        }
        
        let finalDuration = max(1.0, recordingDuration)
        
        // Generate real auto-zoom keyframes from user clicks
        let keyframes = autoZoomEngine.generateKeyframes(
            from: rawEvents,
            totalDuration: finalDuration,
            preferredEffectType: preferredEffectType,
            autoZoomOnTyping: autoZoomOnTyping
        )
        
        // Save telemetry data
        let telemetryURL = finalVideoURL.deletingPathExtension().appendingPathExtension("json")
        if let eventData = try? JSONEncoder().encode(rawEvents) {
            try? eventData.write(to: telemetryURL)
        }
        
        // Create full project
        let project = ClipFocusProject(
            title: finalVideoURL.deletingPathExtension().lastPathComponent,
            duration: max(1.0, finalDuration),
            rawVideoFilename: finalVideoURL.path,
            telemetryFilename: telemetryURL.path,
            aspectRatio: .widescreen16x9,
            zoomKeyframes: keyframes
        )
        
        await MainActor.run {
            self.isRecording = false
            self.isPaused = false
            self.lastRecordedProject = project
        }
        
        return (finalVideoURL, project)
    }
}
