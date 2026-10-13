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
    public private(set) var isLowDiskSpacePaused: Bool = false
    public private(set) var availableDiskSpaceBytes: Int64? = nil
    public private(set) var recordingDuration: TimeInterval = 0.0
    public private(set) var hasScreenCapturePermission: Bool = false
    public private(set) var currentOutputFileURL: URL?
    public private(set) var lastRecordedProject: ClipFocusProject?
    public private(set) var lastErrorMessage: String?
    
    /// Optional Auto-Stop duration in seconds (e.g. 1800 for 30 minutes). When elapsed, invokes onAutoStopTriggered.
    public var autoStopDuration: TimeInterval? = nil
    public var onAutoStopTriggered: (@Sendable () -> Void)? = nil
    
    /// Callback triggered when available disk space drops below safe threshold (300 MB) and recording is auto-paused.
    public var onLowDiskSpacePaused: (@Sendable (Int64) -> Void)? = nil
    
    /// Safe minimum disk space buffer (300 MB) to prevent AVAssetWriter failure and file corruption
    public static let minimumDiskSpaceBytes: Int64 = 300 * 1024 * 1024
    
    private let captureEngine = ScreenCaptureEngine()
    private let cursorTracker = CursorTracker()
    private let autoZoomEngine = AutoZoomEngine()
    private var durationTimer: Timer?
    private var accumulatedDuration: TimeInterval = 0.0
    private var lastResumeTime: Date?
    private var pauseDate: Date?
    private var lastDiskCheckTime: Date = .distantPast
    private var diskCheckInterval: TimeInterval = 5.0
    
    public init() {
        checkPermissions()
    }
    
    /// Query remaining disk space on the volume containing the target URL
    public static func queryAvailableDiskSpace(for url: URL? = nil) -> Int64? {
        let targetURL = url ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/")
        if let values = try? targetURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
            if let important = values.volumeAvailableCapacityForImportantUsage {
                return important
            } else if let standard = values.volumeAvailableCapacity {
                return Int64(standard)
            }
        }
        return nil
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
        targetDisplayID: CGDirectDisplayID? = nil,
        captureMicrophoneAudio: Bool = true,
        captureSystemAudio: Bool = true,
        targetMicrophoneName: String? = nil,
        sourceRect: CGRect? = nil,
        targetWindowID: CGWindowID? = nil,
        targetWindowCocoaRect: CGRect? = nil,
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
        
        // Proactive pre-flight check: Ensure there is at least 300 MB free before recording starts
        if let initialAvailable = CaptureManager.queryAvailableDiskSpace(for: outputDir),
           initialAvailable < CaptureManager.minimumDiskSpaceBytes {
            let mb = initialAvailable / (1024 * 1024)
            throw NSError(
                domain: "ClipFocus",
                code: 507,
                userInfo: [NSLocalizedDescriptionKey: "Ruang penyimpanan hampir habis (tersisa \(mb) MB). Diperlukan minimal 300 MB untuk memulai rekaman. Silakan bersihkan ruang disk terlebih dahulu."]
            )
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestampStr = formatter.string(from: Date())
        let videoURL = outputDir.appendingPathComponent("ClipFocus_\(timestampStr).mov")
        
        // Resolve target screen accurately for external monitor or window recording
        let targetScreen: NSScreen?
        if let id = targetDisplayID {
            targetScreen = NSScreen.screens.first(where: { s in
                let rawNum = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                return (rawNum ?? (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)) == id
            })
        } else if let winRect = targetWindowCocoaRect {
            targetScreen = NSScreen.screens.first(where: { $0.frame.intersects(winRect) })
        } else {
            targetScreen = NSScreen.main ?? NSScreen.screens.first
        }
        
        let scale = targetScreen?.backingScaleFactor ?? 2.0
        let screenWidth = Int(ceil((targetScreen?.frame.width ?? 1920) * scale))
        let screenHeight = Int(ceil((targetScreen?.frame.height ?? 1080) * scale))
        
        let config = CaptureSessionConfig(
            targetDisplayID: targetDisplayID,
            captureWidth: screenWidth > 0 ? screenWidth : 1920,
            captureHeight: screenHeight > 0 ? screenHeight : 1080,
            frameRate: 60,
            captureSystemAudio: captureSystemAudio,
            captureMicrophoneAudio: captureMicrophoneAudio,
            targetMicrophoneName: targetMicrophoneName,
            showHardwareCursor: false, // System cursor hidden: styled vector cursor is rendered from telemetry (Screen Studio style)
            sourceRect: sourceRect,
            targetWindowID: targetWindowID,
            excludedWindowIDs: excludedWindowIDs
        )
        
        // Configure cursor tracker coordinate bounds matching the recorded window or display
        let captureTargetRect: CGRect
        if let winRect = targetWindowCocoaRect {
            captureTargetRect = winRect
        } else if let crop = sourceRect, let screen = targetScreen {
            // Convert crop rect to global Cocoa coordinates if needed
            captureTargetRect = CGRect(x: screen.frame.minX + crop.minX, y: screen.frame.minY + crop.minY, width: crop.width, height: crop.height)
        } else {
            captureTargetRect = targetScreen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        cursorTracker.setCaptureTargetRect(captureTargetRect)
        
        // Start engine and cursor tracker
        try await captureEngine.startCapture(config: config, outputURL: videoURL)
        cursorTracker.startTracking()
        
        await MainActor.run {
            self.currentOutputFileURL = videoURL
            self.isRecording = true
            self.isPaused = false
            self.isLowDiskSpacePaused = false
            self.availableDiskSpaceBytes = nil
            self.lastDiskCheckTime = Date()
            self.diskCheckInterval = 5.0
            self.accumulatedDuration = 0.0
            self.recordingDuration = 0.0
            self.lastResumeTime = Date()
            self.pauseDate = nil
            self.lastErrorMessage = nil
            
            // Duration ticker with Auto-Stop threshold evaluation & Adaptive Low-Disk monitor (0% CPU overhead)
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, self.isRecording, !self.isPaused, let resume = self.lastResumeTime else { return }
                let current = self.accumulatedDuration + Date().timeIntervalSince(resume)
                self.recordingDuration = current
                
                if let limit = self.autoStopDuration, limit > 0, current >= limit {
                    self.autoStopDuration = nil
                    self.onAutoStopTriggered?()
                }
                
                // Adaptive disk space monitoring: throttled and evaluated in background queue
                let now = Date()
                if now.timeIntervalSince(self.lastDiskCheckTime) >= self.diskCheckInterval {
                    self.lastDiskCheckTime = now
                    self.performPeriodicDiskCheck()
                }
            }
        }
    }
    
    /// Throttled, non-blocking disk capacity check to safely auto-pause before disk fills up completely
    private func performPeriodicDiskCheck() {
        guard let outputURL = self.currentOutputFileURL else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let available = CaptureManager.queryAvailableDiskSpace(for: outputURL) else { return }
            
            DispatchQueue.main.async {
                guard let self = self, self.isRecording else { return }
                
                // Adaptive interval:
                // > 5 GB free: check every 6.0s (0% impact)
                // 1 GB - 5 GB free: check every 3.0s
                // < 1 GB free: check every 1.5s
                if available > 5 * 1024 * 1024 * 1024 {
                    self.diskCheckInterval = 6.0
                } else if available > 1024 * 1024 * 1024 {
                    self.diskCheckInterval = 3.0
                } else {
                    self.diskCheckInterval = 1.5
                }
                
                if available < CaptureManager.minimumDiskSpaceBytes && !self.isPaused {
                    self.pauseDueToLowDiskSpace(availableBytes: available)
                }
            }
        }
    }
    
    /// Automatically pause recording due to critically low disk space (< 300 MB)
    private func pauseDueToLowDiskSpace(availableBytes: Int64) {
        guard isRecording, !isPaused else { return }
        pauseRecording()
        isLowDiskSpacePaused = true
        availableDiskSpaceBytes = availableBytes
        onLowDiskSpacePaused?(availableBytes)
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
        
        // If recording was paused due to low disk space, re-verify available capacity
        if isLowDiskSpacePaused {
            if let available = CaptureManager.queryAvailableDiskSpace(for: currentOutputFileURL),
               available < CaptureManager.minimumDiskSpaceBytes {
                self.availableDiskSpaceBytes = available
                return
            }
            self.isLowDiskSpacePaused = false
            self.availableDiskSpaceBytes = nil
        }
        
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
            self.isLowDiskSpacePaused = false
            self.availableDiskSpaceBytes = nil
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
            hasBakedHardwareCursor: false,
            zoomKeyframes: keyframes
        )
        
        await MainActor.run {
            self.isRecording = false
            self.isPaused = false
            self.isLowDiskSpacePaused = false
            self.availableDiskSpaceBytes = nil
            self.lastRecordedProject = project
        }
        
        return (finalVideoURL, project)
    }
}
