import Foundation
import SwiftUI
import AVFoundation
import ClipFocusCore
import AppKit
import ScreenCaptureKit

public enum AppViewMode {
    case launcher
    case floatingControlBar
    case recording
    case editor
}

public enum RecordingMode: String, CaseIterable, Identifiable {
    case fullScreen = "Full Screen"
    case custom = "Custom"
    case window = "Window"
    
    public var id: String { rawValue }
}

public enum ZoomEffectDimension: String, CaseIterable, Identifiable {
    case twoD = "2D"
    case threeD = "3D"
    public var id: String { rawValue }
}

public enum CountdownDuration: Int, CaseIterable, Identifiable {
    case none = 0
    case threeSeconds = 3
    case fiveSeconds = 5
    public var id: Int { rawValue }
}

@Observable
public final class AppState: @unchecked Sendable {
    public var currentView: AppViewMode = .launcher {
        didSet {
            DispatchQueue.main.async {
                WindowManager.shared.updateWindows()
            }
        }
    }
    public var selectedMode: RecordingMode? = nil // None selected initially by default
    public var showPermissionsWindow: Bool = false {
        didSet {
            DispatchQueue.main.async {
                WindowManager.shared.updateWindows()
            }
        }
    }
    public var showPermissionPrompt: Bool = false
    public var errorMessage: String? = nil
    public var isFinalizingRecording: Bool = false
    
    // Recording bar settings matching FocuSee
    public var zoomDimension: ZoomEffectDimension = .twoD
    public var countdownSeconds: CountdownDuration = .threeSeconds
    public var autoZoomOnTyping: Bool = true
    public var hideDesktopIcons: Bool = false {
        didSet {
            setDesktopIconsHidden(hideDesktopIcons)
        }
    }
    public var isCountingDown: Bool = false
    public var countdownValue: Int = 3
    
    // Hardware options
    public var selectedCamera: String = "None"
    public var hasCameraPermission: Bool = false
    public var showCameraPermissionAlert: Bool = false
    public var availableCameras: [String] = ["None"]
    
    public var selectedMic: String = "None"
    public var availableMics: [String] = ["None"]
    
    public var selectedAudio: String = "None"
    public let availableAudio: [String] = ["None", "Mac System Audio"]
    
    // Target Recording Area & Selection (Full Screen, Custom, Window)
    public var customCropRect: CGRect = CGRect(x: 200, y: 150, width: 800, height: 500)
    public var selectedWindowID: CGWindowID? = nil
    public var selectedWindowFrame: CGRect? = nil
    public var selectedWindowName: String? = nil
    public var hoveredWindowID: CGWindowID? = nil
    public var hoveredWindowFrame: CGRect? = nil
    public var hoveredWindowName: String? = nil
    
    // Real Video Recording & Playback
    public var recordedVideoURL: URL? = nil
    public var avPlayer: AVPlayer? = nil
    public var videoAspectRatio: CGFloat = {
        if let screen = NSScreen.main {
            return screen.frame.width / max(1.0, screen.frame.height)
        }
        return 16.0 / 10.0
    }()
    public var zoomKeyframes: [ZoomKeyframe] = []
    public var currentZoomScale: CGFloat = 1.0
    public var currentFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    public var currentPitch: Double = 0.0
    public var currentYaw: Double = 0.0
    public var currentRoll: Double = 0.0
    public var currentPositionX: CGFloat = 0.0
    public var currentPositionY: CGFloat = 0.0
    public var currentIs3D: Bool = true
    
    // FocuSee Controls
    public var disableZoom: Bool = false
    public var selectedEffectType: ZoomEffectType = .motion3D
    public var selectedTiltPreset: TiltPreset = .auto
    
    // Custom 3D rotation angles (used when selectedTiltPreset == .custom)
    public var customPitch: Double = 0.0
    public var customYaw: Double = 0.0
    public var customRoll: Double = 0.0
    public var positionOffsetX: CGFloat = 0.0
    public var positionOffsetY: CGFloat = 0.0
    public var defaultZoomScale: CGFloat = 1.0 // 1X default
    
    public func selectKeyframe(id: UUID) {
        guard let kf = zoomKeyframes.first(where: { $0.id == id }) else { return }
        selectedKeyframeID = id
        selectedEffectType = kf.effectType
        selectedTiltPreset = kf.tiltPreset
        customPitch = kf.customPitch
        customYaw = kf.customYaw
        customRoll = kf.customRoll
        positionOffsetX = kf.positionOffsetX
        positionOffsetY = kf.positionOffsetY
        defaultZoomScale = kf.scale
        self.currentTime = kf.startTime
        self.avPlayer?.seek(to: CMTime(seconds: kf.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        evaluateCurrentZoom()
    }
    
    // Zoom scale of the currently selected keyframe or default (1.0x to 4.0x)
    public var activeZoomScale: CGFloat {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.scale
            }
            return defaultZoomScale
        }
        set {
            let clamped = max(1.0, min(4.0, newValue))
            defaultZoomScale = clamped
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].scale = clamped
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeEffectType: ZoomEffectType {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.effectType
            }
            return selectedEffectType
        }
        set {
            selectedEffectType = newValue
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].effectType = newValue
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeTiltPreset: TiltPreset {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.tiltPreset
            }
            return selectedTiltPreset
        }
        set {
            selectedTiltPreset = newValue
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].tiltPreset = newValue
                if newValue == .custom {
                    zoomKeyframes[idx].effectType = .motion3D
                    // If custom angles are all zero, inherit current auto angles so transition to custom is continuous
                    if zoomKeyframes[idx].customPitch == 0 && zoomKeyframes[idx].customYaw == 0 && zoomKeyframes[idx].customRoll == 0 {
                        let autoAngles = TiltPreset.auto.angles(focusPoint: zoomKeyframes[idx].focusPoint)
                        let seededPitch = autoAngles.pitch != 0 ? autoAngles.pitch : -8.0
                        let seededYaw = autoAngles.yaw != 0 ? autoAngles.yaw : 12.0
                        let seededRoll = autoAngles.roll
                        zoomKeyframes[idx].customPitch = seededPitch
                        zoomKeyframes[idx].customYaw = seededYaw
                        zoomKeyframes[idx].customRoll = seededRoll
                        self.customPitch = seededPitch
                        self.customYaw = seededYaw
                        self.customRoll = seededRoll
                    }
                } else if newValue == .auto {
                    zoomKeyframes[idx].effectType = .motion3D
                }
            }
            evaluateCurrentZoom()
        }
    }
    
    // Custom 3D Rotation active computed properties
    public var activeCustomPitch: Double {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.customPitch
            }
            return customPitch
        }
        set {
            customPitch = newValue
            selectedTiltPreset = .custom
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].customPitch = newValue
                zoomKeyframes[idx].tiltPreset = .custom
                zoomKeyframes[idx].effectType = .motion3D
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeCustomYaw: Double {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.customYaw
            }
            return customYaw
        }
        set {
            customYaw = newValue
            selectedTiltPreset = .custom
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].customYaw = newValue
                zoomKeyframes[idx].tiltPreset = .custom
                zoomKeyframes[idx].effectType = .motion3D
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeCustomRoll: Double {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.customRoll
            }
            return customRoll
        }
        set {
            customRoll = newValue
            selectedTiltPreset = .custom
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].customRoll = newValue
                zoomKeyframes[idx].tiltPreset = .custom
                zoomKeyframes[idx].effectType = .motion3D
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activePositionX: CGFloat {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.positionOffsetX
            }
            return positionOffsetX
        }
        set {
            positionOffsetX = newValue
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].positionOffsetX = newValue
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activePositionY: CGFloat {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.positionOffsetY
            }
            return positionOffsetY
        }
        set {
            positionOffsetY = newValue
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].positionOffsetY = newValue
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeDuration: Double {
        get {
            if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
                return kf.duration
            }
            return 2.5
        }
        set {
            let clamped = max(0.5, min(totalDuration, newValue))
            let targetIdx = selectedKeyframeID != nil ? zoomKeyframes.firstIndex(where: { $0.id == selectedKeyframeID }) : (zoomKeyframes.isEmpty ? nil : 0)
            if let idx = targetIdx {
                selectedKeyframeID = zoomKeyframes[idx].id
                zoomKeyframes[idx].duration = clamped
            }
            evaluateCurrentZoom()
        }
    }
    
    public func applyToAll3DMotions() {
        for idx in zoomKeyframes.indices {
            zoomKeyframes[idx].effectType = selectedEffectType
            zoomKeyframes[idx].tiltPreset = selectedTiltPreset
            zoomKeyframes[idx].customPitch = customPitch
            zoomKeyframes[idx].customYaw = customYaw
            zoomKeyframes[idx].customRoll = customRoll
            zoomKeyframes[idx].scale = activeZoomScale
            zoomKeyframes[idx].positionOffsetX = positionOffsetX
            zoomKeyframes[idx].positionOffsetY = positionOffsetY
        }
        evaluateCurrentZoom()
    }
    
    // Editor styling properties matching Screenshot 2
    public var canvasRatio: String = "16:9"
    public var customWidth: String = "16"
    public var customHeight: String = "9"
    
    public var padding: Double = 10.0
    public var inset: Double = 0.0
    public var roundness: Double = 4.0
    public var shadow: Double = 20.0
    
    // 3D Cinematic Zoom Engine (FocuSee / Screen Studio style)
    public var is3DZoomEnabled: Bool = true
    public var tiltIntensity: Double = 1.0
    
    public var activeBackgroundIndex: Int = 0
    public var activeColorIndex: Int? = nil
    
    // Timeline & Playback
    public var currentTime: Double = 0.0
    public var totalDuration: Double = 12.0
    public var isPlaying: Bool = false
    public var playbackSpeed: Double = 1.0
    public var audioVolume: Double = 1.0
    public var isScrubbing: Bool = false
    public var selectedKeyframeID: UUID? = nil
    
    // Export Pipeline
    public var isExporting: Bool = false
    public var exportProgress: Double = 0.0
    public var exportSuccessMessage: String? = nil
    
    public var telemetryEvents: [TelemetryEvent] = []
    public let captureManager = CaptureManager.shared
    private let autoZoomEngine = AutoZoomEngine()
    private var timeObserverToken: Any?
    
    public init() {
        checkPermissions()
        refreshHardwareDevices()
    }
    
    public func checkPermissions() {
        captureManager.checkPermissions()
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraPermission = (camStatus == .authorized)
        refreshHardwareDevices()
    }
    
    private var hasInitializedAudioDevices = false
    private var hasInitializedVideoDevices = false
    
    public func refreshHardwareDevices() {
        // Video devices
        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let camNames = videoDiscovery.devices.map(\.localizedName)
        self.availableCameras = ["None"] + camNames
        
        if !hasInitializedVideoDevices {
            if hasCameraPermission && !camNames.isEmpty {
                selectedCamera = camNames[0]
                hasInitializedVideoDevices = true
            }
        } else {
            // Only fall back if the user's previously chosen physical camera is no longer connected
            if selectedCamera != "None" && !availableCameras.contains(selectedCamera) {
                selectedCamera = "None"
            }
        }
        
        // Audio devices
        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let micNames = audioDiscovery.devices.map(\.localizedName)
        self.availableMics = ["None"] + micNames
        
        if !hasInitializedAudioDevices {
            if !micNames.isEmpty {
                selectedMic = micNames[0]
                hasInitializedAudioDevices = true
            }
        } else {
            // Only fall back if the user's previously chosen physical mic was unplugged/disconnected
            if selectedMic != "None" && !availableMics.contains(selectedMic) {
                selectedMic = "None"
            }
        }
    }
    
    public func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.hasCameraPermission = granted
                    self.refreshHardwareDevices()
                }
            }
        case .authorized:
            self.hasCameraPermission = true
            refreshHardwareDevices()
        case .denied, .restricted:
            self.hasCameraPermission = false
            self.showCameraPermissionAlert = true
        @unknown default:
            break
        }
    }
    
    /// User selects a mode on the launcher (e.g. Full Screen) -> opens the bottom floating control bar
    public func selectMode(_ mode: RecordingMode) {
        self.selectedMode = mode
        self.currentView = .floatingControlBar
    }
    
    /// User clicks "X" on the floating control bar -> returns to launcher
    public func closeControlBar() {
        self.selectedMode = nil
        self.currentView = .launcher
    }
    
    /// User clicks "More Settings" from floating control bar popup menu
    public func openMoreSettings() {
        closeControlBar()
    }
    
    private func setDesktopIconsHidden(_ hidden: Bool) {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"]
        try? task.run()
        task.waitUntilExit()
        
        let killTask = Process()
        killTask.launchPath = "/usr/bin/killall"
        killTask.arguments = ["Finder"]
        try? killTask.run()
    }
    
    /// User clicks circular "REC" on the floating control bar
    public func startCountdownAndRecord() {
        checkPermissions()
        
        guard CGPreflightScreenCaptureAccess() else {
            self.showPermissionsWindow = true
            return
        }
        
        if countdownSeconds == .none {
            executeStartRecording()
        } else {
            isCountingDown = true
            countdownValue = countdownSeconds.rawValue
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                self.countdownValue -= 1
                if self.countdownValue <= 0 {
                    timer.invalidate()
                    self.isCountingDown = false
                    self.executeStartRecording()
                }
            }
        }
    }
    
    public func triggerStartRecording() {
        startCountdownAndRecord()
    }
    
    private func executeStartRecording() {
        Task { @MainActor in
            do {
                var sourceRect: CGRect? = nil
                var targetWindowID: CGWindowID? = nil
                
                switch self.selectedMode {
                case .fullScreen, .none:
                    sourceRect = nil
                    targetWindowID = nil
                case .custom:
                    sourceRect = self.customCropRect
                    targetWindowID = nil
                case .window:
                    sourceRect = nil
                    if let winID = self.selectedWindowID {
                        targetWindowID = winID
                    } else if let hoverID = self.hoveredWindowID {
                        targetWindowID = hoverID
                    } else {
                        // Auto-discover topmost non-ClipFocus active window
                        let excluded = WindowManager.shared.allClipFocusWindowIDs()
                        if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) {
                            let topWin = content.windows.first { w in
                                !excluded.contains(w.windowID) &&
                                w.frame.width > 200 &&
                                w.frame.height > 200 &&
                                w.owningApplication?.applicationName != "ClipFocus"
                            }
                            targetWindowID = topWin?.windowID
                        }
                    }
                }
                
                let excluded = WindowManager.shared.allClipFocusWindowIDs()
                
                try await self.captureManager.startRecording(
                    mode: self.selectedMode?.rawValue ?? "Full Screen",
                    captureMicrophoneAudio: self.selectedMic != "None",
                    captureSystemAudio: self.selectedAudio != "None",
                    sourceRect: sourceRect,
                    targetWindowID: targetWindowID,
                    excludedWindowIDs: excluded
                )
                self.currentView = .recording
            } catch {
                self.errorMessage = error.localizedDescription
                self.showPermissionsWindow = true
            }
        }
    }
    
    /// Pause or resume current recording
    public var isRecordingPaused: Bool {
        captureManager.isPaused
    }
    
    public func togglePauseRecording() {
        if captureManager.isPaused {
            captureManager.resumeRecording()
        } else {
            captureManager.pauseRecording()
        }
    }
    
    /// Discard current recording and restart immediately from 00:00
    public func restartRecording() {
        Task { @MainActor in
            do {
                try await self.captureManager.discardRecording()
                self.executeStartRecording()
            } catch {
                NSLog("Failed to restart recording: %@", error.localizedDescription)
            }
        }
    }
    
    /// Discard current recording, delete files, and return to launcher
    public func discardRecording() {
        Task { @MainActor in
            do {
                try await self.captureManager.discardRecording()
                self.cleanupEditorPlayback()
                self.currentView = .launcher
                self.selectedMode = nil
            } catch {
                NSLog("Failed to discard recording: %@", error.localizedDescription)
            }
        }
    }
    
    /// Trigger stop recording and load real video into editor
    public func triggerStopRecording() {
        guard !isFinalizingRecording else { return }
        isFinalizingRecording = true
        
        Task { @MainActor in
            defer {
                self.isFinalizingRecording = false
            }
            do {
                let (videoURL, project) = try await self.captureManager.stopRecording()
                guard FileManager.default.fileExists(atPath: videoURL.path),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: videoURL.path),
                      (attrs[.size] as? Int64 ?? 0) > 1024 else {
                    throw NSError(domain: "ClipFocus", code: 500, userInfo: [NSLocalizedDescriptionKey: "Recorded video is empty or too short. Please record for at least 2-3 seconds."])
                }
                self.loadRecordedVideo(url: videoURL, project: project)
            } catch {
                self.errorMessage = "\(error.localizedDescription)"
                self.cleanupEditorPlayback()
                self.currentView = .launcher
            }
        }
    }
    
    /// Load any video into the editor (recorded or imported)
    public func loadRecordedVideo(url: URL, project: ClipFocusProject? = nil) {
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.size] as? Int64 ?? 0) > 1024 else {
            self.errorMessage = "Cannot open video: file is empty or corrupted."
            self.currentView = .launcher
            return
        }
        
        self.recordedVideoURL = url
        self.totalDuration = max(1.0, project?.duration ?? 10.0)
        
        // Load telemetry events from project or adjacent json
        var loadedEvents: [TelemetryEvent] = []
        if let telPath = project?.telemetryFilename, !telPath.isEmpty, FileManager.default.fileExists(atPath: telPath) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: telPath)),
               let evs = try? JSONDecoder().decode([TelemetryEvent].self, from: data) {
                loadedEvents = evs
            }
        } else {
            let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
            if FileManager.default.fileExists(atPath: jsonURL.path),
               let data = try? Data(contentsOf: jsonURL),
               let evs = try? JSONDecoder().decode([TelemetryEvent].self, from: data) {
                loadedEvents = evs
            }
        }
        self.telemetryEvents = loadedEvents
        
        // Populate keyframes from telemetry or generate smart default 3D zoom keyframes
        var keyframes = project?.zoomKeyframes ?? []
        if keyframes.isEmpty {
            let dur = max(2.0, self.totalDuration)
            if dur >= 5.0 {
                keyframes = [
                    ZoomKeyframe(
                        startTime: 1.0,
                        duration: min(3.0, dur * 0.35),
                        focusPoint: CGPoint(x: 0.28, y: 0.32),
                        scale: 2.5,
                        easing: .springSmooth,
                        isAutoGenerated: true,
                        reason: "3D Cinematic Tilt"
                    ),
                    ZoomKeyframe(
                        startTime: min(dur - 2.5, dur * 0.55),
                        duration: min(3.0, dur * 0.35),
                        focusPoint: CGPoint(x: 0.72, y: 0.38),
                        scale: 2.5,
                        easing: .springSmooth,
                        isAutoGenerated: true,
                        reason: "3D Perspective Focus"
                    )
                ]
            } else {
                keyframes = [
                    ZoomKeyframe(
                        startTime: 0.5,
                        duration: max(1.5, dur - 0.8),
                        focusPoint: CGPoint(x: 0.30, y: 0.35),
                        scale: 2.5,
                        easing: .springSmooth,
                        isAutoGenerated: true,
                        reason: "3D Cinematic Tilt"
                    )
                ]
            }
        }
        
        self.zoomKeyframes = keyframes
        self.currentTime = 0.0
        self.selectedKeyframeID = self.zoomKeyframes.first?.id
        
        // Setup AVPlayer
        let player = AVPlayer(url: url)
        self.avPlayer = player
        self.setVolume(self.audioVolume)
        
        // Load real asset duration and natural aspect ratio asynchronously
        let asset = AVURLAsset(url: url)
        Task {
            if let dur = try? await asset.load(.duration), dur.seconds > 0.2 {
                await MainActor.run {
                    self.totalDuration = dur.seconds
                }
            }
            if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
                if let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
                    let isRotated = (transform.a == 0 && abs(transform.b) == 1)
                    let w = isRotated ? size.height : size.width
                    let h = isRotated ? size.width : size.height
                    if w > 10 && h > 10 {
                        await MainActor.run {
                            self.videoAspectRatio = CGFloat(w) / CGFloat(h)
                        }
                    }
                }
            }
        }
        
        // Setup periodic time observer for smooth timeline scrubbing & auto-zoom
        let interval = CMTime(seconds: 0.03, preferredTimescale: 600)
        self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            if !self.isScrubbing {
                self.currentTime = time.seconds
                self.evaluateCurrentZoom()
                if self.currentTime >= self.totalDuration {
                    self.pauseVideo()
                }
            }
        }
        
        self.currentView = .editor
        self.playVideo()
    }
    
    /// Open macOS file picker to import any existing video for auto-zoom editing
    public func importLocalVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.title = "Select Video to Edit with ClipFocus Auto-Zoom"
        
        if panel.runModal() == .OK, let url = panel.url {
            let asset = AVAsset(url: url)
            Task {
                let duration = (try? await asset.load(.duration))?.seconds ?? 10.0
                await MainActor.run {
                    self.loadRecordedVideo(url: url, project: ClipFocusProject(
                        title: url.deletingPathExtension().lastPathComponent,
                        duration: duration,
                        rawVideoFilename: url.path,
                        telemetryFilename: ""
                    ))
                }
            }
        }
    }
    
    public func playVideo() {
        avPlayer?.rate = Float(playbackSpeed)
        isPlaying = true
    }
    
    public func pauseVideo() {
        avPlayer?.pause()
        isPlaying = false
    }
    
    public func togglePlayback() {
        if isPlaying {
            pauseVideo()
        } else {
            playVideo()
        }
    }
    
    public func setPlaybackSpeed(_ speed: Double) {
        self.playbackSpeed = speed
        if isPlaying {
            avPlayer?.rate = Float(speed)
        }
    }
    
    public func setVolume(_ volume: Double) {
        self.audioVolume = volume
        avPlayer?.volume = Float(volume)
    }
    
    private var lastSeekTimestamp: TimeInterval = 0
    
    public func seek(to seconds: Double, accurate: Bool = false) {
        let clamped = max(0, min(totalDuration, seconds))
        currentTime = clamped
        
        let now = ProcessInfo.processInfo.systemUptime
        if accurate || (now - lastSeekTimestamp) > 0.033 {
            lastSeekTimestamp = now
            let targetCMTime = CMTime(seconds: clamped, preferredTimescale: 600)
            let tol: CMTime = accurate ? .zero : CMTime(value: 1, timescale: 30)
            avPlayer?.seek(to: targetCMTime, toleranceBefore: tol, toleranceAfter: tol)
        }
        evaluateCurrentZoom()
    }
    
    /// Clean up AVPlayer and release video file resources when leaving editor
    public func cleanupEditorPlayback() {
        self.timeObserverToken = nil
        self.avPlayer?.pause()
        self.avPlayer?.replaceCurrentItem(with: nil)
        self.avPlayer = nil
        self.isPlaying = false
    }
    
    // MARK: - Keyframe Management
    
    public func addZoomKeyframe(at time: Double) {
        let initialScale = defaultZoomScale > 1.05 ? defaultZoomScale : 2.0
        defaultZoomScale = initialScale
        let newKeyframe = ZoomKeyframe(
            startTime: max(0, time),
            duration: min(2.5, max(1.0, totalDuration - time)),
            focusPoint: currentFocusPoint,
            scale: initialScale,
            easing: .springSmooth,
            effectType: selectedEffectType,
            tiltPreset: selectedTiltPreset,
            customPitch: customPitch,
            customYaw: customYaw,
            customRoll: customRoll,
            positionOffsetX: positionOffsetX,
            positionOffsetY: positionOffsetY,
            isAutoGenerated: false,
            reason: "manual"
        )
        zoomKeyframes.append(newKeyframe)
        zoomKeyframes.sort { $0.startTime < $1.startTime }
        selectedKeyframeID = newKeyframe.id
        self.currentTime = newKeyframe.startTime
        self.avPlayer?.seek(to: CMTime(seconds: newKeyframe.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        evaluateCurrentZoom()
    }
    
    public func deleteZoomKeyframe(id: UUID) {
        zoomKeyframes.removeAll { $0.id == id }
        if selectedKeyframeID == id {
            selectedKeyframeID = zoomKeyframes.first?.id
        }
        evaluateCurrentZoom()
    }
    
    public func updateKeyframeStartTime(id: UUID, newStartTime: Double) {
        if let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            let dur = zoomKeyframes[idx].duration
            
            // Find neighbor boundaries to prevent overlap
            let otherKeyframes = zoomKeyframes.filter { $0.id != id }.sorted { $0.startTime < $1.startTime }
            let prevKF = otherKeyframes.filter { $0.startTime < zoomKeyframes[idx].startTime }.last
            let nextKF = otherKeyframes.filter { $0.startTime >= zoomKeyframes[idx].startTime }.first
            
            let minStart = prevKF != nil ? (prevKF!.startTime + prevKF!.duration + 0.10) : 0.0
            let maxStart = nextKF != nil ? max(minStart, nextKF!.startTime - dur - 0.10) : max(minStart, totalDuration - dur)
            
            let clampedStart = max(minStart, min(maxStart, newStartTime))
            zoomKeyframes[idx].startTime = clampedStart
            evaluateCurrentZoom()
        }
    }
    
    public func updateKeyframeDuration(id: UUID, newDuration: Double) {
        if let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            let start = zoomKeyframes[idx].startTime
            
            // Find next neighbor boundary to prevent overlap
            let otherKeyframes = zoomKeyframes.filter { $0.id != id }.sorted { $0.startTime < $1.startTime }
            let nextKF = otherKeyframes.filter { $0.startTime > start }.first
            
            let maxAllowedDur = nextKF != nil ? max(0.3, nextKF!.startTime - start - 0.10) : max(0.3, totalDuration - start)
            zoomKeyframes[idx].duration = max(0.3, min(maxAllowedDur, newDuration))
            evaluateCurrentZoom()
        }
    }
    
    public func trimKeyframeStart(id: UUID, newStartTime: Double) {
        if let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            let oldEnd = zoomKeyframes[idx].startTime + zoomKeyframes[idx].duration
            
            // Find previous neighbor boundary to prevent overlap
            let otherKeyframes = zoomKeyframes.filter { $0.id != id }.sorted { $0.startTime < $1.startTime }
            let prevKF = otherKeyframes.filter { $0.startTime < zoomKeyframes[idx].startTime }.last
            
            let minAllowedStart = prevKF != nil ? (prevKF!.startTime + prevKF!.duration + 0.10) : 0.0
            let maxAllowedStart = max(minAllowedStart, oldEnd - 0.3)
            
            let clampedStart = max(minAllowedStart, min(maxAllowedStart, newStartTime))
            zoomKeyframes[idx].startTime = clampedStart
            zoomKeyframes[idx].duration = max(0.3, oldEnd - clampedStart)
            evaluateCurrentZoom()
        }
    }
    
    public func finalizeKeyframeEdits() {
        zoomKeyframes.sort { $0.startTime < $1.startTime }
        evaluateCurrentZoom()
    }
    
    public func splitAtCurrentTime() {
        let t = currentTime
        if let idx = zoomKeyframes.firstIndex(where: { t > $0.startTime + 0.3 && t < ($0.startTime + $0.duration - 0.3) }) {
            let original = zoomKeyframes[idx]
            let firstDuration = t - original.startTime
            let secondDuration = original.duration - firstDuration
            
            zoomKeyframes[idx].duration = firstDuration
            
            let secondPart = ZoomKeyframe(
                startTime: t,
                duration: secondDuration,
                focusPoint: original.focusPoint,
                scale: original.scale,
                easing: original.easing,
                effectType: original.effectType,
                tiltPreset: original.tiltPreset,
                customPitch: original.customPitch,
                customYaw: original.customYaw,
                customRoll: original.customRoll,
                positionOffsetX: original.positionOffsetX,
                positionOffsetY: original.positionOffsetY,
                isAutoGenerated: false,
                reason: "split"
            )
            zoomKeyframes.append(secondPart)
            zoomKeyframes.sort { $0.startTime < $1.startTime }
            selectedKeyframeID = secondPart.id
            evaluateCurrentZoom()
        } else {
            addZoomKeyframe(at: t)
        }
    }
    
    /// Apply a 3D cinematic camera perspective preset at current playhead position
    public func apply3DAnglePreset(focusPoint: CGPoint, label: String, scale: CGFloat = 2.5) {
        let t = currentTime
        let keyframe = ZoomKeyframe(
            startTime: max(0, t - 0.2),
            duration: 3.0,
            focusPoint: focusPoint,
            scale: scale,
            easing: .springSmooth,
            effectType: selectedEffectType,
            tiltPreset: selectedTiltPreset,
            customPitch: customPitch,
            customYaw: customYaw,
            customRoll: customRoll,
            positionOffsetX: positionOffsetX,
            positionOffsetY: positionOffsetY,
            isAutoGenerated: false,
            reason: label
        )
        // If an existing keyframe is within 0.5s, update it, otherwise insert new
        if let idx = zoomKeyframes.firstIndex(where: { abs($0.startTime - t) < 0.8 }) {
            zoomKeyframes[idx] = keyframe
        } else {
            zoomKeyframes.append(keyframe)
            zoomKeyframes.sort { $0.startTime < $1.startTime }
        }
        selectedKeyframeID = keyframe.id
        evaluateCurrentZoom()
    }
    
    // MARK: - Real Video Export
    
    public func exportVideo() {
        guard let sourceURL = recordedVideoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "ClipFocus_\(sourceURL.deletingPathExtension().lastPathComponent)_Export.mp4"
        savePanel.title = "Export Video"
        
        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }
        
        try? FileManager.default.removeItem(at: destinationURL)
        
        isExporting = true
        exportProgress = 0.1
        
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            isExporting = false
            self.errorMessage = "Could not initialize video exporter."
            return
        }
        
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if exportSession.status == .exporting {
                self.exportProgress = max(0.1, Double(exportSession.progress))
            }
        }
        
        exportSession.exportAsynchronously { [weak self] in
            timer.invalidate()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isExporting = false
                if exportSession.status == .completed {
                    self.exportProgress = 1.0
                    self.exportSuccessMessage = "Video exported successfully!"
                    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                } else {
                    self.errorMessage = "Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")"
                }
            }
        }
    }
    
    public func evaluateCurrentZoom() {
        if disableZoom {
            self.currentZoomScale = 1.0
            self.currentFocusPoint = CGPoint(x: 0.5, y: 0.5)
            self.currentPitch = 0.0
            self.currentYaw = 0.0
            self.currentRoll = 0.0
            self.currentPositionX = 0.0
            self.currentPositionY = 0.0
            self.currentIs3D = false
            return
        }
        
        if isPlaying || isScrubbing {
            // Dynamic playback & scrubbing evaluation
            let viewport = autoZoomEngine.evaluateViewport(at: currentTime, with: zoomKeyframes, telemetry: telemetryEvents)
            self.currentZoomScale = viewport.scale
            self.currentFocusPoint = viewport.focusPoint
            self.currentPitch = viewport.pitch * tiltIntensity
            self.currentYaw = viewport.yaw * tiltIntensity
            self.currentRoll = viewport.roll * tiltIntensity
            self.currentPositionX = viewport.positionOffsetX
            self.currentPositionY = viewport.positionOffsetY
            self.currentIs3D = viewport.is3D
        } else if let id = selectedKeyframeID, let kf = zoomKeyframes.first(where: { $0.id == id }) {
            // Paused with a keyframe selected: reflect that keyframe's live values & 3D angles immediately
            let is3D = kf.effectType == .motion3D
            let angles = is3D ? kf.resolvedAngles : (pitch: 0.0, yaw: 0.0, roll: 0.0)
            self.currentZoomScale = kf.scale
            self.currentFocusPoint = kf.focusPoint
            self.currentPitch = angles.pitch * tiltIntensity
            self.currentYaw = angles.yaw * tiltIntensity
            self.currentRoll = angles.roll * tiltIntensity
            self.currentPositionX = kf.positionOffsetX
            self.currentPositionY = kf.positionOffsetY
            self.currentIs3D = is3D
        } else {
            let viewport = autoZoomEngine.evaluateViewport(at: currentTime, with: zoomKeyframes, telemetry: telemetryEvents)
            self.currentZoomScale = viewport.scale
            self.currentFocusPoint = viewport.focusPoint
            self.currentPitch = viewport.pitch * tiltIntensity
            self.currentYaw = viewport.yaw * tiltIntensity
            self.currentRoll = viewport.roll * tiltIntensity
            self.currentPositionX = viewport.positionOffsetX
            self.currentPositionY = viewport.positionOffsetY
            self.currentIs3D = viewport.is3D
        }
    }
}
