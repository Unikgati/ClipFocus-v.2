import Foundation
import SwiftUI
import AVFoundation
import ClipFocusCore
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

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
    
    public var userConfiguredMic: Bool = false
    public var selectedMic: String = "None" {
        didSet {
            userConfiguredMic = true
        }
    }
    public var hasMicPermission: Bool = false
    public var showMicPermissionAlert: Bool = false
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
    
    // Real Video Recording, Playback & Project File Management
    public var recordedVideoURL: URL? = nil
    public var currentProjectURL: URL? = nil
    public var projectTitle: String = "Untitled Project"
    public var currentProjectCreatedAt: Date? = nil
    public var isDirty: Bool = false
    public var showSaveSuccessToast: Bool = false
    public var avPlayer: AVPlayer? = nil
    public var videoAspectRatio: CGFloat = {
        if let screen = NSScreen.main {
            return screen.frame.width / max(1.0, screen.frame.height)
        }
        return 16.0 / 10.0
    }()
    public var zoomKeyframes: [ZoomKeyframe] = []
    public var videoSegments: [MediaClipSegment] = []
    public var audioSegments: [MediaClipSegment] = []
    public var selectedSegmentIDs: Set<UUID> = []
    public var selectedKeyframeIDs: Set<UUID> = []
    
    public var selectedSegmentID: UUID? {
        get { selectedSegmentIDs.first }
        set {
            if let newID = newValue {
                selectedSegmentIDs = [newID]
            } else {
                selectedSegmentIDs.removeAll()
            }
        }
    }
    public var selectedTrackType: TimelineTrackType? = nil
    public var isVideoTrackHidden: Bool = false
    public var isZoomTrackHidden: Bool = false
    public var isSnappingEnabled: Bool = true
    public var currentZoomScale: CGFloat = 1.0
    public var currentFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    public var currentPitch: Double = 0.0
    public var currentYaw: Double = 0.0
    public var currentRoll: Double = 0.0
    public var currentPositionX: CGFloat = 0.0
    public var currentPositionY: CGFloat = 0.0
    public var currentIs3D: Bool = false
    public var previewArtboardSize: CGSize = .zero
    
    // FocuSee Controls
    public var disableZoom: Bool = false
    public var selectedEffectType: ZoomEffectType = .zoom2D
    public var selectedTiltPreset: TiltPreset = .flat
    
    // Custom 3D rotation angles (used when selectedTiltPreset == .custom)
    public var customPitch: Double = 0.0
    public var customYaw: Double = 0.0
    public var customRoll: Double = 0.0
    public var positionOffsetX: CGFloat = 0.0
    public var positionOffsetY: CGFloat = 0.0
    public var defaultZoomScale: CGFloat = 1.0 // 1X default
    
    public func selectKeyframe(id: UUID, isAdd: Bool = false, isRange: Bool = false, seekTime: Double? = nil) {
        guard let kf = zoomKeyframes.first(where: { $0.id == id }) else { return }
        selectedSegmentIDs.removeAll()
        selectedTrackType = nil
        
        if isRange, let lastID = selectedKeyframeIDs.first, let lastKf = zoomKeyframes.first(where: { $0.id == lastID }) {
            let minTime = min(lastKf.startTime, kf.startTime)
            let maxTime = max(lastKf.startTime + lastKf.duration, kf.startTime + kf.duration)
            let inRange = zoomKeyframes.filter { $0.startTime >= (minTime - 0.01) && ($0.startTime + $0.duration) <= (maxTime + 0.01) }
            for item in inRange {
                selectedKeyframeIDs.insert(item.id)
            }
        } else if isAdd {
            if selectedKeyframeIDs.contains(id) {
                selectedKeyframeIDs.remove(id)
            } else {
                selectedKeyframeIDs.insert(id)
            }
        } else {
            selectedKeyframeIDs = [id]
        }
        
        selectedEffectType = kf.effectType
        selectedTiltPreset = kf.tiltPreset
        customPitch = kf.customPitch
        customYaw = kf.customYaw
        customRoll = kf.customRoll
        positionOffsetX = kf.positionOffsetX
        positionOffsetY = kf.positionOffsetY
        defaultZoomScale = kf.scale
        
        // Seek playhead: if custom seekTime is provided, use it;
        // otherwise only seek if playhead is outside the keyframe's boundary to avoid displacing paused frame
        if let targetSeek = seekTime {
            self.currentTime = targetSeek
            self.avPlayer?.seek(to: CMTime(seconds: targetSeek, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else if !(currentTime >= kf.startTime && currentTime <= (kf.startTime + kf.duration)) {
            let defaultSeek = kf.startTime + min(0.6, kf.duration / 2.0)
            self.currentTime = defaultSeek
            self.avPlayer?.seek(to: CMTime(seconds: defaultSeek, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        evaluateCurrentZoom()
    }
    
    public func selectMultipleKeyframes(ids: Set<UUID>, isAdd: Bool = false) {
        selectedSegmentIDs.removeAll()
        selectedTrackType = nil
        if isAdd {
            selectedKeyframeIDs.formUnion(ids)
        } else {
            selectedKeyframeIDs = ids
        }
        if let firstID = selectedKeyframeIDs.first, let kf = zoomKeyframes.first(where: { $0.id == firstID }) {
            selectedEffectType = kf.effectType
            selectedTiltPreset = kf.tiltPreset
            defaultZoomScale = kf.scale
        }
    }
    
    /// Returns the index of the actively selected zoom keyframe, if any (Pure read-only)
    public func selectedKeyframeIndex() -> Int? {
        if let id = selectedKeyframeID, let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return nil
    }

    // Zoom scale of the currently selected keyframe or default (1.0x to 4.0x)
    public var activeZoomScale: CGFloat {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].scale
            }
            return defaultZoomScale
        }
        set {
            let clamped = max(1.0, min(4.0, newValue))
            defaultZoomScale = clamped
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].scale = clamped
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeEffectType: ZoomEffectType {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].effectType
            }
            return selectedEffectType
        }
        set {
            selectedEffectType = newValue
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].effectType = newValue
                if newValue == .zoom2D {
                    zoomKeyframes[idx].tiltPreset = .flat
                    selectedTiltPreset = .flat
                } else if newValue == .motion3D {
                    if zoomKeyframes[idx].tiltPreset == .flat {
                        zoomKeyframes[idx].tiltPreset = .auto
                        selectedTiltPreset = .auto
                    }
                }
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeTiltPreset: TiltPreset {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].tiltPreset
            }
            return selectedTiltPreset
        }
        set {
            selectedTiltPreset = newValue
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].tiltPreset = newValue
                if newValue == .custom {
                    zoomKeyframes[idx].effectType = .motion3D
                    selectedEffectType = .motion3D
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
                    selectedEffectType = .motion3D
                } else if newValue == .flat {
                    zoomKeyframes[idx].effectType = .zoom2D
                    selectedEffectType = .zoom2D
                }
            }
            evaluateCurrentZoom()
        }
    }
    
    // Custom 3D Rotation active computed properties
    public var activeCustomPitch: Double {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].customPitch
            }
            return customPitch
        }
        set {
            customPitch = newValue
            selectedTiltPreset = .custom
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].customPitch = newValue
                zoomKeyframes[idx].tiltPreset = .custom
                zoomKeyframes[idx].effectType = .motion3D
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeCustomYaw: Double {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].customYaw
            }
            return customYaw
        }
        set {
            customYaw = newValue
            selectedTiltPreset = .custom
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].customYaw = newValue
                zoomKeyframes[idx].tiltPreset = .custom
                zoomKeyframes[idx].effectType = .motion3D
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeCustomRoll: Double {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].customRoll
            }
            return customRoll
        }
        set {
            customRoll = newValue
            selectedTiltPreset = .custom
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].customRoll = newValue
                zoomKeyframes[idx].tiltPreset = .custom
                zoomKeyframes[idx].effectType = .motion3D
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activePositionX: CGFloat {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].positionOffsetX
            }
            return positionOffsetX
        }
        set {
            positionOffsetX = newValue
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].positionOffsetX = newValue
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activePositionY: CGFloat {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].positionOffsetY
            }
            return positionOffsetY
        }
        set {
            positionOffsetY = newValue
            if let idx = selectedKeyframeIndex() {
                zoomKeyframes[idx].positionOffsetY = newValue
            }
            evaluateCurrentZoom()
        }
    }
    
    public var activeDuration: Double {
        get {
            if let idx = selectedKeyframeIndex() {
                return zoomKeyframes[idx].duration
            }
            return 2.5
        }
        set {
            let clamped = max(0.5, min(totalDuration, newValue))
            if let idx = selectedKeyframeIndex() {
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
    public var exportResolution: String = "1080p" // "1080p", "2K", "4K", "Auto"
    
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
    public var timelineZoomScale: Double = 1.0
    public var isScrubbing: Bool = false
    public var selectedKeyframeID: UUID? {
        get { selectedKeyframeIDs.first }
        set {
            if let newID = newValue {
                selectedKeyframeIDs = [newID]
            } else {
                selectedKeyframeIDs.removeAll()
            }
        }
    }
    
    // Export Pipeline
    public var isExporting: Bool = false
    public var exportProgress: Double = 0.0
    public var exportSuccessMessage: String? = nil
    public var lastExportedURL: URL? = nil
    private var isSavePanelActive: Bool = false
    private var activeExportSession: AVAssetExportSession? = nil
    
    public func cancelExport() {
        activeExportSession?.cancelExport()
        activeExportSession = nil
        isExporting = false
        exportProgress = 0.0
    }
    
    public var telemetryEvents: [TelemetryEvent] = []
    public let captureManager = CaptureManager.shared
    private let autoZoomEngine = AutoZoomEngine()
    private var timeObserverToken: Any?
    private var playbackDisplayTimer: Timer?
    private var cachedSourceAsset: AVURLAsset? = nil
    private var cachedVideoTrack: AVAssetTrack? = nil
    private var cachedAudioTracks: [AVAssetTrack] = []
    private var cachedVideoTransform: CGAffineTransform = .identity
    
    public init() {
        checkPermissions()
        refreshHardwareDevices()
    }
    
    public func checkPermissions() {
        captureManager.checkPermissions()
        // Webcam recording is disabled for now - no camera permission checks needed
        hasCameraPermission = true
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicPermission = (micStatus == .authorized)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasMicPermission = granted
                    self.refreshHardwareDevices()
                }
            }
        }
        
        refreshHardwareDevices()
    }
    
    private var hasInitializedAudioDevices = false
    
    public func refreshHardwareDevices() {
        // Video devices discovery disabled for now
        self.availableCameras = ["None"]
        self.selectedCamera = "None"
        
        // Audio devices
        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let micNames = audioDiscovery.devices.map(\.localizedName)
        self.availableMics = ["None"] + micNames
        
        if !hasInitializedAudioDevices {
            hasInitializedAudioDevices = true
            if !userConfiguredMic && !micNames.isEmpty {
                selectedMic = micNames[0]
            }
        } else {
            // Only fall back if the user's previously chosen physical mic was unplugged/disconnected
            if selectedMic != "None" && !availableMics.contains(selectedMic) {
                selectedMic = "None"
            }
        }
    }
    
    public func requestCameraPermission() {
        // No-op while webcam recording is disabled
        self.hasCameraPermission = true
    }
    
    public func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasMicPermission = granted
                    self.refreshHardwareDevices()
                }
            }
        case .authorized:
            self.hasMicPermission = true
            refreshHardwareDevices()
        case .denied, .restricted:
            self.hasMicPermission = false
            self.showMicPermissionAlert = true
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
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
                
                let isMicActive = (self.selectedMic != "None" && !self.selectedMic.isEmpty)
                let isAudioActive = (self.selectedAudio != "None" && !self.selectedAudio.isEmpty)
                
                try await self.captureManager.startRecording(
                    mode: self.selectedMode?.rawValue ?? "Full Screen",
                    captureMicrophoneAudio: isMicActive,
                    captureSystemAudio: isAudioActive,
                    targetMicrophoneName: isMicActive ? self.selectedMic : nil,
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
                // Allow ScreenCaptureKit to cleanly release previous stream before immediate restart
                try? await Task.sleep(nanoseconds: 250_000_000)
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
                let effectType: ZoomEffectType = (self.zoomDimension == .threeD) ? .motion3D : .zoom2D
                let (videoURL, project) = try await self.captureManager.stopRecording(
                    preferredEffectType: effectType,
                    autoZoomOnTyping: self.autoZoomOnTyping
                )
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
    
    public var isAudioMuted: Bool = false
    public var audioWaveformSamples: [Float] = []
    
    public func loadAudioWaveform(from url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
                  let track = audioTracks.first else {
                await MainActor.run {
                    self.audioWaveformSamples = []
                    if self.audioSegments.count <= 1 {
                        self.audioSegments = []
                    }
                }
                return
            }
            
            do {
                let reader = try AVAssetReader(asset: asset)
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
                guard reader.canAdd(trackOutput) else { return }
                reader.add(trackOutput)
                reader.startReading()
                
                let assetDur = (try? await asset.load(.duration).seconds) ?? self.totalDuration
                let dur = assetDur > 0.1 ? assetDur : max(1.0, self.totalDuration)
                let targetSampleCount = max(600, min(2400, Int(dur * 50)))
                var buckets = [Float](repeating: 0.0, count: targetSampleCount)
                
                while reader.status == .reading {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                       let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                        let bDur = CMSampleBufferGetDuration(sampleBuffer).seconds
                        let length = CMBlockBufferGetDataLength(blockBuffer)
                        let numSamples = length / 2
                        
                        var data = Data(count: length)
                        data.withUnsafeMutableBytes { bytes in
                            if let base = bytes.baseAddress {
                                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                            }
                        }
                        data.withUnsafeBytes { (int16Ptr: UnsafeRawBufferPointer) in
                            let buffer = int16Ptr.bindMemory(to: Int16.self)
                            let chunkSize = 128
                            for chunkStart in stride(from: 0, to: numSamples, by: chunkSize) {
                                let chunkEnd = min(numSamples, chunkStart + chunkSize)
                                var maxAmp: Float = 0
                                for idx in stride(from: chunkStart, to: chunkEnd, by: 4) {
                                    let amp = abs(Float(buffer[idx])) / 32768.0
                                    if amp > maxAmp { maxAmp = amp }
                                }
                                
                                let frac = Double(chunkStart) / Double(max(1, numSamples))
                                let t = pts + (frac * bDur)
                                let bucketIdx = Int((t / dur) * Double(targetSampleCount))
                                if bucketIdx >= 0 && bucketIdx < targetSampleCount {
                                    if maxAmp > buckets[bucketIdx] {
                                        buckets[bucketIdx] = maxAmp
                                    }
                                }
                            }
                        }
                    } else {
                        break
                    }
                }
                
                var condensed = [Float](repeating: 0.0, count: targetSampleCount)
                for i in 0..<targetSampleCount {
                    let peak = buckets[i]
                    // Strict noise gate: mic hiss and room floor below -42 dB (< 0.008) is true 0.0 silence
                    if peak < 0.008 {
                        condensed[i] = 0.0
                    } else {
                        // Perceptual power scale (pow 0.65) for crisp speech dynamics
                        let scaled = Float(pow(Double(peak), 0.65)) * 1.25
                        condensed[i] = min(1.0, scaled)
                    }
                }
                
                let finalCondensed = condensed
                await MainActor.run {
                    self.audioWaveformSamples = finalCondensed
                }
            } catch {
                NSLog("Waveform extraction failed: %@", error.localizedDescription)
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
        self.projectTitle = project?.title ?? url.deletingPathExtension().lastPathComponent
        self.currentProjectCreatedAt = project?.createdAt ?? Date()
        self.isDirty = false
        self.startAutosaveTimer()
        
        // Load telemetry events from embedded project, external project path, or adjacent json
        var loadedEvents: [TelemetryEvent] = []
        if let embedded = project?.embeddedTelemetry, !embedded.isEmpty {
            loadedEvents = embedded
        } else if let telPath = project?.telemetryFilename, !telPath.isEmpty, FileManager.default.fileExists(atPath: telPath) {
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
        
        // Populate keyframes directly from project (empty if user did not click during recording)
        let keyframes = project?.zoomKeyframes ?? []
        self.zoomKeyframes = keyframes
        self.currentTime = 0.0
        self.selectedKeyframeID = nil
        self.selectedSegmentID = nil
        self.selectedTrackType = nil
        
        // Populate video and audio segments from project or default full-span clips
        if let vSegs = project?.videoSegments, !vSegs.isEmpty {
            self.videoSegments = vSegs
        } else {
            self.videoSegments = [
                MediaClipSegment(
                    trackType: .video,
                    name: url.deletingPathExtension().lastPathComponent,
                    sourceStartTime: 0.0,
                    timelineStartTime: 0.0,
                    duration: self.totalDuration,
                    isMuted: false,
                    volume: 1.0
                )
            ]
        }
        
        if let aSegs = project?.audioSegments, !aSegs.isEmpty {
            self.audioSegments = aSegs
        } else {
            self.audioSegments = [
                MediaClipSegment(
                    trackType: .audio,
                    name: self.selectedMic != "None" ? self.selectedMic : "Audio Stream",
                    sourceStartTime: 0.0,
                    timelineStartTime: 0.0,
                    duration: self.totalDuration,
                    isMuted: false,
                    volume: 1.0
                )
            ]
        }
        
        self.clearHistory()
        
        // Setup initial AVPlayer
        let player = AVPlayer()
        self.avPlayer = player
        self.setupTimeObserver(for: player)
        self.setVolume(self.audioVolume)
        
        // Asynchronously extract audio waveform for timeline visualization
        self.loadAudioWaveform(from: url)
        
        // Load real asset duration and natural aspect ratio asynchronously
        let asset = AVURLAsset(url: url)
        self.cachedSourceAsset = asset
        Task {
            if let dur = try? await asset.load(.duration), dur.seconds > 0.2 {
                await MainActor.run {
                    self.totalDuration = dur.seconds
                    if self.videoSegments.count == 1 && self.videoSegments[0].timelineStartTime == 0 {
                        self.videoSegments[0].duration = dur.seconds
                    }
                    if self.audioSegments.count == 1 && self.audioSegments[0].timelineStartTime == 0 {
                        self.audioSegments[0].duration = dur.seconds
                    }
                }
            }
            let vTracks = try? await asset.loadTracks(withMediaType: .video)
            let aTracks = try? await asset.loadTracks(withMediaType: .audio)
            let firstVTrack = vTracks?.first
            
            var aspect: CGFloat = 16.0 / 9.0
            var vTransform: CGAffineTransform = .identity
            if let track = firstVTrack {
                if let transform = try? await track.load(.preferredTransform) {
                    vTransform = transform
                }
                if let size = try? await track.load(.naturalSize) {
                    let isRotated = (vTransform.a == 0 && abs(vTransform.b) == 1)
                    let w = isRotated ? size.height : size.width
                    let h = isRotated ? size.width : size.height
                    if w > 10 && h > 10 {
                        aspect = CGFloat(w) / CGFloat(h)
                    }
                }
            }
            let finalTransform = vTransform
            let finalAspect = aspect
            await MainActor.run {
                self.cachedVideoTrack = firstVTrack
                self.cachedAudioTracks = aTracks ?? []
                self.cachedVideoTransform = finalTransform
                self.videoAspectRatio = finalAspect
                self.rebuildPlaybackComposition(maintainPlayhead: false)
            }
        }
        
        self.currentView = .editor
        self.pauseVideo()
        self.seek(to: 0.0, accurate: true)
    }
    
    // MARK: - Gapless NLE Playback Composition Engine
    
    public func rebuildPlaybackComposition(maintainPlayhead: Bool = true) {
        guard let url = recordedVideoURL else { return }
        
        let asset: AVURLAsset
        if let cached = cachedSourceAsset, cached.url == url {
            asset = cached
        } else {
            asset = AVURLAsset(url: url)
            cachedSourceAsset = asset
        }
        
        if cachedVideoTrack == nil && !videoSegments.isEmpty {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.cachedVideoTrack = (try? await asset.loadTracks(withMediaType: .video))?.first
                self.cachedAudioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
                if let vTrack = self.cachedVideoTrack, let transform = try? await vTrack.load(.preferredTransform) {
                    self.cachedVideoTransform = transform
                }
                self.executeRebuildComposition(asset: asset, maintainPlayhead: maintainPlayhead)
            }
        } else {
            executeRebuildComposition(asset: asset, maintainPlayhead: maintainPlayhead)
        }
    }
    
    private func executeRebuildComposition(asset: AVURLAsset, maintainPlayhead: Bool) {
        let composition = AVMutableComposition()
        
        // 1. Video Track
        if !isVideoTrackHidden, let assetVTrack = cachedVideoTrack, !videoSegments.isEmpty {
            if let compVTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                compVTrack.preferredTransform = self.cachedVideoTransform
                
                let sortedVSegs = videoSegments.sorted { $0.timelineStartTime < $1.timelineStartTime }
                for seg in sortedVSegs {
                    guard seg.duration > 0.05 else { continue }
                    let srcRange = CMTimeRange(
                        start: CMTime(seconds: seg.sourceStartTime, preferredTimescale: 600),
                        duration: CMTime(seconds: seg.duration, preferredTimescale: 600)
                    )
                    let atTime = CMTime(seconds: seg.timelineStartTime, preferredTimescale: 600)
                    do {
                        try compVTrack.insertTimeRange(srcRange, of: assetVTrack, at: atTime)
                    } catch {
                        NSLog("[ClipFocus] Composition video insert error: %@", error.localizedDescription)
                    }
                }
            }
        }
        
        // 2. Audio Tracks
        if !isAudioMuted, !audioSegments.isEmpty {
            let activeASegs = audioSegments.filter { !$0.isMuted && $0.duration > 0.05 }.sorted { $0.timelineStartTime < $1.timelineStartTime }
            for assetATrack in cachedAudioTracks {
                if let compATrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    for seg in activeASegs {
                        let srcRange = CMTimeRange(
                            start: CMTime(seconds: seg.sourceStartTime, preferredTimescale: 600),
                            duration: CMTime(seconds: seg.duration, preferredTimescale: 600)
                        )
                        let atTime = CMTime(seconds: seg.timelineStartTime, preferredTimescale: 600)
                        do {
                            try compATrack.insertTimeRange(srcRange, of: assetATrack, at: atTime)
                        } catch {
                            NSLog("[ClipFocus] Composition audio insert error: %@", error.localizedDescription)
                        }
                    }
                }
            }
        }
        
        let playerItem = AVPlayerItem(asset: composition)
        let wasPlaying = self.isPlaying
        let targetTime = maintainPlayhead ? min(self.currentTime, self.totalDuration) : 0.0
        
        if let player = self.avPlayer {
            player.replaceCurrentItem(with: playerItem)
        } else {
            let player = AVPlayer(playerItem: playerItem)
            self.avPlayer = player
            setupTimeObserver(for: player)
        }
        
        setVolume(self.audioVolume)
        
        let targetCM = CMTime(seconds: targetTime, preferredTimescale: 600)
        self.avPlayer?.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            if wasPlaying && self.playbackSpeed > 0 {
                self.avPlayer?.rate = Float(self.playbackSpeed)
            }
        }
    }
    
    private func setupTimeObserver(for player: AVPlayer) {
        if let token = self.timeObserverToken {
            self.avPlayer?.removeTimeObserver(token)
            self.timeObserverToken = nil
        }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            if self.isPlaying && !self.isScrubbing && time.seconds >= self.totalDuration {
                self.pauseVideo()
            }
        }
    }
    
    /// Clean up AVPlayer and release video file resources when leaving editor
    public func cleanupEditorPlayback() {
        stopPlaybackDisplayTimer()
        if let token = self.timeObserverToken, let player = self.avPlayer {
            player.removeTimeObserver(token)
        }
        self.timeObserverToken = nil
        self.avPlayer?.pause()
        self.avPlayer?.replaceCurrentItem(with: nil)
        self.avPlayer = nil
        self.isPlaying = false
    }
    
    // MARK: - Keyframe Management
    
    public func addZoomKeyframe(at time: Double) {
        // If clicking inside an existing keyframe, select it
        if let existing = zoomKeyframes.first(where: { time >= $0.startTime && time < ($0.startTime + $0.duration) }) {
            selectKeyframe(id: existing.id)
            return
        }
        
        let initialScale = defaultZoomScale > 1.05 ? defaultZoomScale : 2.0
        defaultZoomScale = initialScale
        let start = max(0, time)
        
        // Find next keyframe to clamp duration and prevent overlapping (dynamic space support)
        let nextKF = zoomKeyframes.filter { $0.startTime > start }.sorted { $0.startTime < $1.startTime }.first
        let maxAllowed = nextKF != nil ? max(0.05, nextKF!.startTime - start) : max(0.05, totalDuration - start)
        let dur = min(3.0, maxAllowed)
        
        let targetFocus = autoZoomEngine.cursorPosition(at: start, from: telemetryEvents, fallback: CGPoint(x: 0.5, y: 0.5))
        
        let newKeyframe = ZoomKeyframe(
            startTime: start,
            duration: dur,
            focusPoint: targetFocus,
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
        selectKeyframe(id: newKeyframe.id)
    }
    
    public func deleteZoomKeyframe(id: UUID) {
        zoomKeyframes.removeAll { $0.id == id }
        if selectedKeyframeID == id {
            selectedKeyframeID = nil
        }
        evaluateCurrentZoom()
    }
    
    public func updateKeyframeStartTime(id: UUID, newStartTime: Double) {
        if let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            let dur = zoomKeyframes[idx].duration
            
            // Find neighbor boundaries to prevent overlap (zero-gap support)
            let otherKeyframes = zoomKeyframes.filter { $0.id != id }.sorted { $0.startTime < $1.startTime }
            let prevKF = otherKeyframes.filter { $0.startTime < zoomKeyframes[idx].startTime }.last
            let nextKF = otherKeyframes.filter { $0.startTime >= zoomKeyframes[idx].startTime }.first
            
            let minStart = prevKF != nil ? (prevKF!.startTime + prevKF!.duration) : 0.0
            let maxStart = nextKF != nil ? max(minStart, nextKF!.startTime - dur) : max(minStart, totalDuration - dur)
            
            let clampedStart = max(minStart, min(maxStart, newStartTime))
            zoomKeyframes[idx].startTime = clampedStart
            evaluateCurrentZoom()
        }
    }
    
    public func updateKeyframeDuration(id: UUID, newDuration: Double) {
        if let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            let start = zoomKeyframes[idx].startTime
            
            // Find next neighbor boundary to prevent overlap (zero-gap support)
            let otherKeyframes = zoomKeyframes.filter { $0.id != id }.sorted { $0.startTime < $1.startTime }
            let nextKF = otherKeyframes.filter { $0.startTime > start }.first
            
            let maxAllowedDur = nextKF != nil ? max(0.2, nextKF!.startTime - start) : max(0.2, totalDuration - start)
            zoomKeyframes[idx].duration = max(0.2, min(maxAllowedDur, newDuration))
            evaluateCurrentZoom()
        }
    }
    
    public func trimKeyframeStart(id: UUID, newStartTime: Double) {
        if let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            let oldEnd = zoomKeyframes[idx].startTime + zoomKeyframes[idx].duration
            
            // Find previous neighbor boundary to prevent overlap (zero-gap support)
            let otherKeyframes = zoomKeyframes.filter { $0.id != id }.sorted { $0.startTime < $1.startTime }
            let prevKF = otherKeyframes.filter { $0.startTime < zoomKeyframes[idx].startTime }.last
            
            let minAllowedStart = prevKF != nil ? (prevKF!.startTime + prevKF!.duration) : 0.0
            let maxAllowedStart = max(minAllowedStart, oldEnd - 0.2)
            
            let clampedStart = max(minAllowedStart, min(maxAllowedStart, newStartTime))
            zoomKeyframes[idx].startTime = clampedStart
            zoomKeyframes[idx].duration = max(0.2, oldEnd - clampedStart)
            evaluateCurrentZoom()
        }
    }
    
    public func finalizeKeyframeEdits() {
        zoomKeyframes.sort { $0.startTime < $1.startTime }
        evaluateCurrentZoom()
    }
    
    // MARK: - Active Timeline Segments & Source Mapping
    
    public func activeVideoSegment(at time: Double) -> MediaClipSegment? {
        guard !isVideoTrackHidden else { return nil }
        return videoSegments.first { time >= $0.timelineStartTime && time < $0.timelineEndTime }
    }
    
    public func activeAudioSegment(at time: Double) -> MediaClipSegment? {
        guard !isAudioMuted else { return nil }
        return audioSegments.first { time >= $0.timelineStartTime && time < $0.timelineEndTime && !$0.isMuted }
    }
    
    public func sourceVideoTime(for timelineTime: Double) -> Double? {
        guard let vSeg = activeVideoSegment(at: timelineTime) else { return nil }
        let offset = max(0, timelineTime - vSeg.timelineStartTime)
        return vSeg.sourceStartTime + offset
    }
    
    public func sourceAudioTime(for timelineTime: Double) -> Double? {
        guard let aSeg = activeAudioSegment(at: timelineTime) else { return nil }
        let offset = max(0, timelineTime - aSeg.timelineStartTime)
        return aSeg.sourceStartTime + offset
    }
    
    public func activeSourceTime(for timelineTime: Double) -> Double? {
        return sourceVideoTime(for: timelineTime) ?? sourceAudioTime(for: timelineTime)
    }
    
    public func syncPlaybackToCurrentTime(accurate: Bool = false) {
        let t = currentTime
        
        // Seek directly in the virtual composition timeline
        let targetCMTime = CMTime(seconds: t, preferredTimescale: 600)
        let tol: CMTime = accurate ? .zero : CMTime(value: 1, timescale: 30)
        avPlayer?.seek(to: targetCMTime, toleranceBefore: tol, toleranceAfter: tol)
        
        // Audio Track Volume / Mute Sync
        let aSeg = activeAudioSegment(at: t)
        let isMute = isAudioMuted || aSeg == nil || (aSeg?.isMuted ?? false)
        avPlayer?.isMuted = isMute
        avPlayer?.volume = isMute ? 0.0 : Float(audioVolume * (aSeg?.volume ?? 1.0))
        
        evaluateCurrentZoom()
    }
    
    public func playVideo() {
        if currentTime >= (totalDuration - 0.05) {
            seek(to: 0.0, accurate: true)
        }
        if playbackSpeed <= 0 {
            playbackSpeed = 1.0
        }
        isPlaying = true
        
        let playerSec = avPlayer?.currentTime().seconds ?? 0
        if abs(playerSec - currentTime) > 0.05 {
            let targetCM = CMTime(seconds: currentTime, preferredTimescale: 600)
            avPlayer?.seek(to: targetCM, toleranceBefore: CMTime(value: 1, timescale: 30), toleranceAfter: CMTime(value: 1, timescale: 30)) { [weak self] _ in
                guard let self = self else { return }
                if self.isPlaying && self.playbackSpeed > 0 {
                    self.avPlayer?.rate = Float(self.playbackSpeed)
                }
            }
        } else {
            avPlayer?.rate = Float(playbackSpeed)
        }
        
        startPlaybackDisplayTimer()
    }
    
    public func pauseVideo() {
        avPlayer?.pause()
        isPlaying = false
        stopPlaybackDisplayTimer()
    }
    
    private func startPlaybackDisplayTimer() {
        stopPlaybackDisplayTimer()
        playbackDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying, !self.isScrubbing else { return }
            guard let player = self.avPlayer else { return }
            
            let playerSec = player.currentTime().seconds
            if playerSec >= self.totalDuration {
                self.currentTime = self.totalDuration
                self.pauseVideo()
                self.syncPlaybackToCurrentTime(accurate: true)
                return
            }
            
            // Advance timeline smoothly locked directly to AVPlayer hardware audio clock
            self.currentTime = max(0.0, playerSec)
            
            // Audio Track Volume / Mute Sync
            let aSeg = self.activeAudioSegment(at: self.currentTime)
            let isMute = self.isAudioMuted || aSeg == nil || (aSeg?.isMuted ?? false)
            if player.isMuted != isMute {
                player.isMuted = isMute
            }
            let targetVol = isMute ? 0.0 : Float(self.audioVolume * (aSeg?.volume ?? 1.0))
            if player.volume != targetVol {
                player.volume = targetVol
            }
            
            self.evaluateCurrentZoom()
        }
        if let timer = playbackDisplayTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func stopPlaybackDisplayTimer() {
        playbackDisplayTimer?.invalidate()
        playbackDisplayTimer = nil
    }
    
    public func togglePlayback() {
        if isPlaying {
            pauseVideo()
        } else {
            playVideo()
        }
    }
    
    /// Premiere Pro style Shuttle Forward (L): 1x -> 2x -> 4x -> 8x
    public func shuttleForward() {
        if !isPlaying || playbackSpeed <= 0 {
            playbackSpeed = 1.0
            playVideo()
        } else {
            if playbackSpeed < 2.0 {
                setPlaybackSpeed(2.0)
            } else if playbackSpeed < 4.0 {
                setPlaybackSpeed(4.0)
            } else {
                setPlaybackSpeed(8.0)
            }
        }
    }
    
    /// Premiere Pro style Shuttle Reverse (J): -1x -> -2x -> -4x -> -8x
    public func shuttleReverse() {
        if currentTime <= 0.05 {
            seek(to: totalDuration, accurate: true)
        }
        if !isPlaying || playbackSpeed >= 0 {
            avPlayer?.pause()
            playbackSpeed = -1.0
            isPlaying = true
            startPlaybackDisplayTimer()
        } else {
            if playbackSpeed > -2.0 {
                playbackSpeed = -2.0
            } else if playbackSpeed > -4.0 {
                playbackSpeed = -4.0
            } else {
                playbackSpeed = -8.0
            }
        }
    }
    
    /// Premiere Pro style Shuttle Stop (K)
    public func shuttleStop() {
        pauseVideo()
        playbackSpeed = 1.0
    }
    
    public func jumpToStart() {
        seek(to: 0.0, accurate: true)
    }
    
    public func jumpToEnd() {
        seek(to: totalDuration, accurate: true)
    }
    
    public func stepBackward(seconds: Double = 1.0) {
        seek(to: max(0.0, currentTime - seconds), accurate: false)
    }
    
    public func stepForward(seconds: Double = 1.0) {
        seek(to: min(totalDuration, currentTime + seconds), accurate: false)
    }
    
    public func setPlaybackSpeed(_ speed: Double) {
        self.playbackSpeed = speed
        if isPlaying && speed > 0 {
            avPlayer?.rate = Float(speed)
        }
    }
    
    public func setVolume(_ volume: Double) {
        self.audioVolume = volume
        if activeAudioSegment(at: currentTime) != nil {
            avPlayer?.volume = Float(volume)
        } else {
            avPlayer?.volume = 0.0
        }
    }
    
    private var lastSeekTimestamp: TimeInterval = 0
    
    public func seek(to seconds: Double, accurate: Bool = false) {
        let clamped = max(0, min(totalDuration, seconds))
        currentTime = clamped
        
        let now = ProcessInfo.processInfo.systemUptime
        if accurate || (now - lastSeekTimestamp) > 0.033 {
            lastSeekTimestamp = now
            syncPlaybackToCurrentTime(accurate: accurate)
        } else {
            evaluateCurrentZoom()
        }
    }
    
    public func previewHover(at seconds: Double) {
        guard !isPlaying && !isScrubbing else { return }
        let clamped = max(0, min(totalDuration, seconds))
        let now = ProcessInfo.processInfo.systemUptime
        if (now - lastSeekTimestamp) > 0.033 {
            lastSeekTimestamp = now
            let targetCMTime = CMTime(seconds: clamped, preferredTimescale: 600)
            let tol = CMTime(value: 1, timescale: 30)
            avPlayer?.seek(to: targetCMTime, toleranceBefore: tol, toleranceAfter: tol)
        }
    }
    
    public func endHoverPreview() {
        guard !isPlaying && !isScrubbing else { return }
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func selectSegment(id: UUID, trackType: TimelineTrackType, isAdd: Bool = false, isRange: Bool = false) {
        selectedKeyframeIDs.removeAll()
        selectedTrackType = trackType
        
        let pool = (trackType == .video ? videoSegments : audioSegments)
        guard let seg = pool.first(where: { $0.id == id }) else { return }
        
        if isRange, let lastID = selectedSegmentIDs.first, let lastSeg = pool.first(where: { $0.id == lastID }) {
            let minTime = min(lastSeg.timelineStartTime, seg.timelineStartTime)
            let maxTime = max(lastSeg.timelineEndTime, seg.timelineEndTime)
            let inRange = pool.filter { $0.timelineStartTime >= (minTime - 0.01) && $0.timelineEndTime <= (maxTime + 0.01) }
            for item in inRange {
                selectedSegmentIDs.insert(item.id)
            }
        } else if isAdd {
            if selectedSegmentIDs.contains(id) {
                selectedSegmentIDs.remove(id)
            } else {
                selectedSegmentIDs.insert(id)
            }
        } else {
            selectedSegmentIDs = [id]
        }
    }
    
    public func selectMultipleSegments(ids: Set<UUID>, trackType: TimelineTrackType, isAdd: Bool = false) {
        selectedKeyframeIDs.removeAll()
        selectedTrackType = trackType
        if isAdd {
            selectedSegmentIDs.formUnion(ids)
        } else {
            selectedSegmentIDs = ids
        }
    }
    
    // MARK: - Undo / Redo History Engine
    private var undoStack: [EditorHistorySnapshot] = []
    private var redoStack: [EditorHistorySnapshot] = []
    
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    
    public func captureHistorySnapshot() -> EditorHistorySnapshot {
        EditorHistorySnapshot(
            videoSegments: self.videoSegments,
            audioSegments: self.audioSegments,
            zoomKeyframes: self.zoomKeyframes,
            selectedSegmentID: self.selectedSegmentID,
            selectedTrackType: self.selectedTrackType,
            selectedKeyframeID: self.selectedKeyframeID,
            isVideoTrackHidden: self.isVideoTrackHidden,
            isZoomTrackHidden: self.isZoomTrackHidden,
            isAudioMuted: self.isAudioMuted,
            canvasRatio: self.canvasRatio,
            activeBackgroundIndex: self.activeBackgroundIndex,
            activeColorIndex: self.activeColorIndex,
            padding: self.padding,
            inset: self.inset,
            roundness: self.roundness,
            shadow: self.shadow,
            playbackSpeed: self.playbackSpeed,
            is3DZoomEnabled: self.is3DZoomEnabled,
            tiltIntensity: self.tiltIntensity,
            selectedSegmentIDs: self.selectedSegmentIDs,
            selectedKeyframeIDs: self.selectedKeyframeIDs
        )
    }
    
    public func recordUndoState() {
        let current = captureHistorySnapshot()
        if let last = undoStack.last, last == current {
            return
        }
        undoStack.append(current)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        self.isDirty = true
    }
    
    public func undo() {
        guard let previousState = undoStack.popLast() else { return }
        let current = captureHistorySnapshot()
        redoStack.append(current)
        restoreHistorySnapshot(previousState)
    }
    
    public func redo() {
        guard let nextState = redoStack.popLast() else { return }
        let current = captureHistorySnapshot()
        undoStack.append(current)
        restoreHistorySnapshot(nextState)
    }
    
    private func restoreHistorySnapshot(_ s: EditorHistorySnapshot) {
        self.videoSegments = s.videoSegments
        self.audioSegments = s.audioSegments
        self.zoomKeyframes = s.zoomKeyframes
        self.selectedSegmentIDs = s.selectedSegmentIDs ?? (s.selectedSegmentID.map { [$0] } ?? [])
        self.selectedKeyframeIDs = s.selectedKeyframeIDs ?? (s.selectedKeyframeID.map { [$0] } ?? [])
        self.selectedTrackType = s.selectedTrackType
        self.isVideoTrackHidden = s.isVideoTrackHidden
        self.isZoomTrackHidden = s.isZoomTrackHidden
        self.isAudioMuted = s.isAudioMuted
        self.canvasRatio = s.canvasRatio
        self.activeBackgroundIndex = s.activeBackgroundIndex
        self.activeColorIndex = s.activeColorIndex
        self.padding = s.padding
        self.inset = s.inset
        self.roundness = s.roundness
        self.shadow = s.shadow
        self.playbackSpeed = s.playbackSpeed
        self.is3DZoomEnabled = s.is3DZoomEnabled
        self.tiltIntensity = s.tiltIntensity
        self.isDirty = true
        
        evaluateCurrentZoom()
        rebuildPlaybackComposition(maintainPlayhead: true)
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    public func clearSelection() {
        self.selectedSegmentIDs.removeAll()
        self.selectedTrackType = nil
        self.selectedKeyframeIDs.removeAll()
    }
    
    public func deleteSelected() {
        recordUndoState()
        var didChange = false
        if !selectedKeyframeIDs.isEmpty {
            zoomKeyframes.removeAll { selectedKeyframeIDs.contains($0.id) }
            selectedKeyframeIDs.removeAll()
            didChange = true
        }
        if !selectedSegmentIDs.isEmpty, let type = selectedTrackType {
            switch type {
            case .video:
                videoSegments.removeAll { selectedSegmentIDs.contains($0.id) }
            case .audio:
                audioSegments.removeAll { selectedSegmentIDs.contains($0.id) }
            case .zoom:
                zoomKeyframes.removeAll { selectedSegmentIDs.contains($0.id) }
            }
            selectedSegmentIDs.removeAll()
            selectedTrackType = nil
            didChange = true
        }
        if didChange {
            evaluateCurrentZoom()
            rebuildPlaybackComposition(maintainPlayhead: true)
            syncPlaybackToCurrentTime(accurate: true)
        }
    }
    
    public func deleteVideoSegment(id: UUID) {
        recordUndoState()
        videoSegments.removeAll { $0.id == id }
        rebuildPlaybackComposition(maintainPlayhead: true)
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func deleteAudioSegment(id: UUID) {
        recordUndoState()
        audioSegments.removeAll { $0.id == id }
        rebuildPlaybackComposition(maintainPlayhead: true)
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func splitAtCurrentTime() {
        let t = currentTime
        var hasSplitAnything = false
        
        let hasSpecificSelection = (selectedSegmentID != nil || selectedKeyframeID != nil)
        
        // 1. Video track split:
        // If a video clip is explicitly selected, split only it.
        // If nothing is selected at all, split any video clip intersecting the playhead.
        let shouldSplitVideo = (!hasSpecificSelection) || (selectedTrackType == .video && selectedSegmentID != nil)
        if shouldSplitVideo {
            if let targetIdx = videoSegments.firstIndex(where: { t > ($0.timelineStartTime + 0.05) && t < ($0.timelineEndTime - 0.05) && (selectedSegmentID == nil || selectedSegmentID == $0.id) }) {
                recordUndoState()
                let original = videoSegments[targetIdx]
                let firstDur = t - original.timelineStartTime
                let secondDur = original.duration - firstDur
                
                videoSegments[targetIdx].duration = firstDur
                
                let secondPart = MediaClipSegment(
                    trackType: .video,
                    name: "\(original.name) (Cut)",
                    sourceStartTime: original.sourceStartTime + firstDur,
                    timelineStartTime: t,
                    duration: secondDur,
                    isMuted: original.isMuted,
                    volume: original.volume
                )
                videoSegments.append(secondPart)
                videoSegments.sort { $0.timelineStartTime < $1.timelineStartTime }
                selectSegment(id: secondPart.id, trackType: .video)
                hasSplitAnything = true
            }
        }
        
        // 2. Audio track split:
        // If an audio clip is explicitly selected, split only it.
        // If nothing is selected at all, split any audio clip intersecting the playhead.
        let shouldSplitAudio = (!hasSpecificSelection) || (selectedTrackType == .audio && selectedSegmentID != nil)
        if shouldSplitAudio {
            if let targetIdx = audioSegments.firstIndex(where: { t > ($0.timelineStartTime + 0.05) && t < ($0.timelineEndTime - 0.05) && (selectedSegmentID == nil || selectedSegmentID == $0.id) }) {
                if !hasSplitAnything {
                    recordUndoState()
                }
                let original = audioSegments[targetIdx]
                let firstDur = t - original.timelineStartTime
                let secondDur = original.duration - firstDur
                
                audioSegments[targetIdx].duration = firstDur
                
                let secondPart = MediaClipSegment(
                    trackType: .audio,
                    name: "\(original.name) (Cut)",
                    sourceStartTime: original.sourceStartTime + firstDur,
                    timelineStartTime: t,
                    duration: secondDur,
                    isMuted: original.isMuted,
                    volume: original.volume
                )
                audioSegments.append(secondPart)
                audioSegments.sort { $0.timelineStartTime < $1.timelineStartTime }
                if !hasSplitAnything {
                    selectSegment(id: secondPart.id, trackType: .audio)
                }
                hasSplitAnything = true
            }
        }
        
        // 3. Zoom keyframe track split:
        // If a zoom block is explicitly selected, split only it.
        // If nothing is selected at all, split any zoom block intersecting the playhead.
        let shouldSplitZoom = (!hasSpecificSelection) || (selectedKeyframeID != nil)
        if shouldSplitZoom {
            if let idx = zoomKeyframes.firstIndex(where: { t > ($0.startTime + 0.05) && t < ($0.startTime + $0.duration - 0.05) && (selectedKeyframeID == nil || selectedKeyframeID == $0.id) }) {
                if !hasSplitAnything {
                    recordUndoState()
                }
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
                if !hasSplitAnything {
                    selectedKeyframeID = secondPart.id
                }
                evaluateCurrentZoom()
                hasSplitAnything = true
            }
        }
        
        if hasSplitAnything {
            rebuildPlaybackComposition(maintainPlayhead: true)
        }
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    // MARK: - Trimming & Repositioning for Video & Audio Segments
    
    public func trimSegmentStart(id: UUID, trackType: TimelineTrackType, newTimelineStart: Double) {
        switch trackType {
        case .video:
            if let idx = videoSegments.firstIndex(where: { $0.id == id }) {
                let seg = videoSegments[idx]
                let oldEnd = seg.timelineEndTime
                let others = videoSegments.filter { $0.id != id }.sorted { $0.timelineStartTime < $1.timelineStartTime }
                let prev = others.filter { $0.timelineStartTime < seg.timelineStartTime }.last
                
                // Cannot overlap previous clip on timeline
                let minTimelineStart = prev != nil ? prev!.timelineEndTime : 0.0
                // Cannot extend before the start of original source video (sourceStartTime >= 0.0)
                let minSourceStart = seg.timelineStartTime - seg.sourceStartTime
                let minStart = max(minTimelineStart, minSourceStart)
                let maxStart = oldEnd - 0.2
                
                let clampedStart = max(minStart, min(maxStart, newTimelineStart))
                let delta = clampedStart - seg.timelineStartTime
                videoSegments[idx].timelineStartTime = clampedStart
                videoSegments[idx].sourceStartTime = max(0.0, seg.sourceStartTime + delta)
                videoSegments[idx].duration = max(0.2, oldEnd - clampedStart)
            }
        case .audio:
            if let idx = audioSegments.firstIndex(where: { $0.id == id }) {
                let seg = audioSegments[idx]
                let oldEnd = seg.timelineEndTime
                let others = audioSegments.filter { $0.id != id }.sorted { $0.timelineStartTime < $1.timelineStartTime }
                let prev = others.filter { $0.timelineStartTime < seg.timelineStartTime }.last
                
                // Cannot overlap previous clip on timeline
                let minTimelineStart = prev != nil ? prev!.timelineEndTime : 0.0
                // Cannot extend before the start of original source audio (sourceStartTime >= 0.0)
                let minSourceStart = seg.timelineStartTime - seg.sourceStartTime
                let minStart = max(minTimelineStart, minSourceStart)
                let maxStart = oldEnd - 0.2
                
                let clampedStart = max(minStart, min(maxStart, newTimelineStart))
                let delta = clampedStart - seg.timelineStartTime
                audioSegments[idx].timelineStartTime = clampedStart
                audioSegments[idx].sourceStartTime = max(0.0, seg.sourceStartTime + delta)
                audioSegments[idx].duration = max(0.2, oldEnd - clampedStart)
            }
        case .zoom:
            trimKeyframeStart(id: id, newStartTime: newTimelineStart)
        }
        syncPlaybackToCurrentTime(accurate: false)
    }
    
    public func trimSegmentEnd(id: UUID, trackType: TimelineTrackType, newDuration: Double) {
        switch trackType {
        case .video:
            if let idx = videoSegments.firstIndex(where: { $0.id == id }) {
                let seg = videoSegments[idx]
                let others = videoSegments.filter { $0.id != id }.sorted { $0.timelineStartTime < $1.timelineStartTime }
                let next = others.filter { $0.timelineStartTime > seg.timelineStartTime }.first
                
                // Cannot extend beyond the end of the original source video file
                let maxSourceDur = max(0.2, totalDuration - seg.sourceStartTime)
                // Cannot overlap next clip or extend beyond timeline totalDuration
                let maxTimelineDur = next != nil ? max(0.2, next!.timelineStartTime - seg.timelineStartTime) : max(0.2, totalDuration - seg.timelineStartTime)
                let maxDur = min(maxSourceDur, maxTimelineDur)
                
                videoSegments[idx].duration = max(0.2, min(maxDur, newDuration))
            }
        case .audio:
            if let idx = audioSegments.firstIndex(where: { $0.id == id }) {
                let seg = audioSegments[idx]
                let others = audioSegments.filter { $0.id != id }.sorted { $0.timelineStartTime < $1.timelineStartTime }
                let next = others.filter { $0.timelineStartTime > seg.timelineStartTime }.first
                
                // Cannot extend beyond the end of the original source audio
                let maxSourceDur = max(0.2, totalDuration - seg.sourceStartTime)
                // Cannot overlap next clip or extend beyond timeline totalDuration
                let maxTimelineDur = next != nil ? max(0.2, next!.timelineStartTime - seg.timelineStartTime) : max(0.2, totalDuration - seg.timelineStartTime)
                let maxDur = min(maxSourceDur, maxTimelineDur)
                
                audioSegments[idx].duration = max(0.2, min(maxDur, newDuration))
            }
        case .zoom:
            updateKeyframeDuration(id: id, newDuration: newDuration)
        }
        syncPlaybackToCurrentTime(accurate: false)
    }
    
    public func moveSegment(id: UUID, trackType: TimelineTrackType, newTimelineStart: Double) {
        switch trackType {
        case .video:
            if let idx = videoSegments.firstIndex(where: { $0.id == id }) {
                let dur = videoSegments[idx].duration
                let others = videoSegments.filter { $0.id != id }.sorted { $0.timelineStartTime < $1.timelineStartTime }
                let prev = others.filter { $0.timelineStartTime < videoSegments[idx].timelineStartTime }.last
                let next = others.filter { $0.timelineStartTime >= videoSegments[idx].timelineStartTime }.first
                let minStart = prev != nil ? prev!.timelineEndTime : 0.0
                let maxStart = next != nil ? max(minStart, next!.timelineStartTime - dur) : max(minStart, totalDuration - dur)
                videoSegments[idx].timelineStartTime = max(minStart, min(maxStart, newTimelineStart))
            }
        case .audio:
            if let idx = audioSegments.firstIndex(where: { $0.id == id }) {
                let dur = audioSegments[idx].duration
                let others = audioSegments.filter { $0.id != id }.sorted { $0.timelineStartTime < $1.timelineStartTime }
                let prev = others.filter { $0.timelineStartTime < audioSegments[idx].timelineStartTime }.last
                let next = others.filter { $0.timelineStartTime >= audioSegments[idx].timelineStartTime }.first
                let minStart = prev != nil ? prev!.timelineEndTime : 0.0
                let maxStart = next != nil ? max(minStart, next!.timelineStartTime - dur) : max(minStart, totalDuration - dur)
                audioSegments[idx].timelineStartTime = max(minStart, min(maxStart, newTimelineStart))
            }
        case .zoom:
            updateKeyframeStartTime(id: id, newStartTime: newTimelineStart)
        }
        syncPlaybackToCurrentTime(accurate: false)
    }
    
    public func toggleVideoTrackVisibility() {
        recordUndoState()
        isVideoTrackHidden.toggle()
        rebuildPlaybackComposition(maintainPlayhead: true)
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func toggleZoomTrackVisibility() {
        recordUndoState()
        isZoomTrackHidden.toggle()
        evaluateCurrentZoom()
    }
    
    public func toggleAudioMute() {
        recordUndoState()
        isAudioMuted.toggle()
        rebuildPlaybackComposition(maintainPlayhead: true)
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    /// Apply a 3D cinematic camera perspective preset at current playhead position
    public func apply3DAnglePreset(focusPoint: CGPoint, label: String, scale: CGFloat = 2.5) {
        recordUndoState()
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
        selectedSegmentID = nil
        selectedTrackType = nil
        evaluateCurrentZoom()
    }
    
    // MARK: - Project File Management (.focusproj)
    
    private var autosaveTimer: Timer? = nil
    
    public var recentProjectURLs: [URL] {
        get {
            let paths = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
            return paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        set {
            let paths = newValue.map { $0.path }
            UserDefaults.standard.set(paths, forKey: "recentProjects")
        }
    }
    
    public func addRecentProject(url: URL) {
        var recents = recentProjectURLs
        recents.removeAll { $0.path == url.path }
        recents.insert(url, at: 0)
        if recents.count > 10 {
            recents = Array(recents.prefix(10))
        }
        recentProjectURLs = recents
    }
    
    /// Save current project edits (⌘S or Save button). If no file chosen yet, triggers Save As.
    @MainActor
    public func saveProject(as saveAs: Bool = false) {
        if !saveAs, let existingURL = currentProjectURL {
            do {
                try saveProjectToFile(at: existingURL)
            } catch {
                NSLog("[ClipFocus] Error saving project: %@", error.localizedDescription)
                errorMessage = "Failed to save project: \(error.localizedDescription)"
            }
            return
        }
        
        guard !isSavePanelActive else { return }
        isSavePanelActive = true
        
        let savePanel = NSSavePanel()
        if let focusType = UTType(filenameExtension: "focusproj") {
            savePanel.allowedContentTypes = [focusType]
        } else {
            savePanel.allowedContentTypes = [.json]
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "\(projectTitle).focusproj"
        savePanel.title = "Save ClipFocus Project"
        
        NSApp.activate(ignoringOtherApps: true)
        let targetWindow = WindowManager.shared.currentEditorWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
        
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self else { return }
            self.isSavePanelActive = false
            guard response == .OK, let destinationURL = savePanel.url else { return }
            do {
                try self.saveProjectToFile(at: destinationURL)
            } catch {
                NSLog("[ClipFocus] Error saving project to file: %@", error.localizedDescription)
                self.errorMessage = "Failed to save project: \(error.localizedDescription)"
            }
        }
        
        if let window = targetWindow, window.attachedSheet == nil {
            window.makeKeyAndOrderFront(nil)
            savePanel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            savePanel.begin(completionHandler: completion)
        }
    }
    
    /// Atomically serialize and save project to disk
    @MainActor
    public func saveProjectToFile(at destinationURL: URL) throws {
        guard let sourceURL = recordedVideoURL else {
            throw NSError(domain: "ClipFocus", code: 404, userInfo: [NSLocalizedDescriptionKey: "No source video associated with this project to save."])
        }
        
        // Calculate relative path if video is in the same directory or child directory
        let projectFolder = destinationURL.deletingLastPathComponent().path
        let videoPath = sourceURL.path
        var relPath: String? = nil
        if videoPath.hasPrefix(projectFolder) {
            let relativePart = String(videoPath.dropFirst(projectFolder.count))
            relPath = relativePart.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relPath = sourceURL.lastPathComponent
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoPath))?[.size] as? Int64
        
        let project = ClipFocusProject(
            title: destinationURL.deletingPathExtension().lastPathComponent,
            schemaVersion: 1,
            appVersion: "1.0.0",
            createdAt: currentProjectCreatedAt ?? Date(),
            updatedAt: Date(),
            duration: totalDuration,
            rawVideoFilename: videoPath,
            relativeVideoPath: relPath,
            videoFileSize: fileSize,
            embeddedTelemetry: self.telemetryEvents,
            aspectRatio: CanvasAspectRatio(rawValue: canvasRatio) ?? .widescreen16x9,
            canvasRatioString: self.canvasRatio,
            exportResolution: self.exportResolution,
            backgroundStyle: CanvasBackgroundStyle(),
            canvasPadding: self.padding,
            canvasCornerRadius: self.roundness,
            canvasShadowRadius: self.shadow,
            canvasShadowOpacity: 0.35,
            activeBackgroundIndex: self.activeBackgroundIndex,
            activeColorIndex: self.activeColorIndex,
            tiltIntensity: self.tiltIntensity,
            disableZoom: self.disableZoom,
            cursorSettings: CursorVisualSettings(),
            webcamSettings: WebcamLayoutSettings(),
            isAudioMuted: self.isAudioMuted,
            audioVolume: self.audioVolume,
            isVideoTrackHidden: self.isVideoTrackHidden,
            isZoomTrackHidden: self.isZoomTrackHidden,
            currentTime: self.currentTime,
            timelineZoomScale: self.timelineZoomScale,
            zoomKeyframes: self.zoomKeyframes,
            subtitles: [],
            videoSegments: self.videoSegments,
            audioSegments: self.audioSegments
        )
        
        try project.saveAtomic(to: destinationURL)
        
        self.currentProjectURL = destinationURL
        self.projectTitle = destinationURL.deletingPathExtension().lastPathComponent
        self.currentProjectCreatedAt = project.createdAt
        self.isDirty = false
        self.clearAutosaveRecovery()
        
        // Add to recent projects
        addRecentProject(url: destinationURL)
        
        // Trigger visual feedback toast
        self.showSaveSuccessToast = true
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self.showSaveSuccessToast = false
            }
        }
        NSLog("[ClipFocus] Project saved successfully at %@", destinationURL.path)
    }
    
    /// Present native Open dialog to choose a .focusproj project or video file
    @MainActor
    public func openProjectDialog() {
        checkUnsavedChanges { [weak self] in
            guard let self = self else { return }
            let openPanel = NSOpenPanel()
            let focusType = UTType(filenameExtension: "focusproj") ?? .json
            openPanel.allowedContentTypes = [focusType, .mpeg4Movie, .quickTimeMovie, .movie]
            openPanel.allowsMultipleSelection = false
            openPanel.canChooseDirectories = false
            openPanel.canChooseFiles = true
            openPanel.title = "Open ClipFocus Project or Video"
            openPanel.prompt = "Open"
            
            NSApp.activate(ignoringOtherApps: true)
            openPanel.begin { [weak self] response in
                guard let self = self, response == .OK, let selectedURL = openPanel.url else { return }
                if selectedURL.pathExtension.lowercased() == "focusproj" {
                    self.loadProject(from: selectedURL)
                } else {
                    self.loadRecordedVideo(url: selectedURL)
                    self.currentView = .editor
                    WindowManager.shared.updateWindows()
                }
            }
        }
    }
    
    /// Load .focusproj document and relink media
    @MainActor
    public func loadProject(from projectURL: URL) {
        do {
            let project = try ClipFocusProject.load(from: projectURL)
            
            // Check if source video asset exists
            if let resolvedVideoURL = project.resolveVideoURL(relativeTo: projectURL) {
                applyLoadedProject(project, videoURL: resolvedVideoURL, projectURL: projectURL)
            } else {
                // Video file missing -> smart relinking prompt
                NSLog("[ClipFocus] Source video missing for project: %@", projectURL.path)
                promptRelinkMissingVideo(for: project, projectURL: projectURL)
            }
        } catch {
            NSLog("[ClipFocus] Failed to load project: %@", error.localizedDescription)
            self.errorMessage = "Failed to load project: \(error.localizedDescription)"
        }
    }
    
    /// Smart Interactive Relinking dialog when video asset was moved or renamed
    @MainActor
    public func promptRelinkMissingVideo(for project: ClipFocusProject, projectURL: URL) {
        let alert = NSAlert()
        let originalName = URL(fileURLWithPath: project.rawVideoFilename).lastPathComponent
        alert.messageText = "Media File Missing"
        alert.informativeText = "The source video \"\(originalName)\" could not be found at its original location.\n\nWould you like to locate and relink this media file?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Locate File...")
        alert.addButton(withTitle: "Cancel")
        
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            let openPanel = NSOpenPanel()
            openPanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
            openPanel.allowsMultipleSelection = false
            openPanel.canChooseDirectories = false
            openPanel.canChooseFiles = true
            openPanel.title = "Locate \"\(originalName)\""
            openPanel.prompt = "Relink"
            
            if openPanel.runModal() == .OK, let relinkedURL = openPanel.url {
                applyLoadedProject(project, videoURL: relinkedURL, projectURL: projectURL)
                self.isDirty = true // Mark dirty since asset location was changed
            }
        }
    }
    
    /// Applies a decoded project and verified video asset into editor state
    @MainActor
    public func applyLoadedProject(_ project: ClipFocusProject, videoURL: URL, projectURL: URL) {
        self.cleanupEditorPlayback()
        
        self.currentProjectURL = projectURL
        self.projectTitle = projectURL.deletingPathExtension().lastPathComponent
        self.currentProjectCreatedAt = project.createdAt
        
        // Load base video player and telemetry
        self.loadRecordedVideo(url: videoURL, project: project)
        
        // Restore all non-destructive canvas styling
        self.canvasRatio = project.canvasRatioString
        self.exportResolution = project.exportResolution
        self.padding = project.canvasPadding
        self.roundness = project.canvasCornerRadius
        self.shadow = project.canvasShadowRadius
        self.activeBackgroundIndex = project.activeBackgroundIndex
        self.activeColorIndex = project.activeColorIndex
        self.tiltIntensity = project.tiltIntensity
        self.disableZoom = project.disableZoom
        
        // Restore audio & track visibility
        self.isAudioMuted = project.isAudioMuted
        self.audioVolume = project.audioVolume
        self.setVolume(project.audioVolume)
        self.isVideoTrackHidden = project.isVideoTrackHidden
        self.isZoomTrackHidden = project.isZoomTrackHidden
        
        // Restore timeline view state
        self.timelineZoomScale = project.timelineZoomScale
        
        // Restore embedded telemetry if present
        if let emb = project.embeddedTelemetry, !emb.isEmpty {
            self.telemetryEvents = emb
        }
        
        self.seek(to: project.currentTime, accurate: true)
        self.clearHistory()
        self.isDirty = false
        self.clearAutosaveRecovery()
        
        addRecentProject(url: projectURL)
        
        self.currentView = .editor
        WindowManager.shared.updateWindows()
        
        NSLog("[ClipFocus] Project successfully loaded from: %@", projectURL.path)
    }
    
    /// Checks for unsaved changes before performing destructive actions (closing, opening new project)
    @MainActor
    public func checkUnsavedChanges(onProceed: @escaping () -> Void) {
        guard isDirty, currentView == .editor, recordedVideoURL != nil else {
            onProceed()
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \"\(projectTitle)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Save
            if let existingURL = currentProjectURL {
                do {
                    try saveProjectToFile(at: existingURL)
                    onProceed()
                } catch {
                    errorMessage = "Failed to save project: \(error.localizedDescription)"
                }
            } else {
                saveProject(as: true)
            }
        case .alertSecondButtonReturn:
            // Don't Save
            self.isDirty = false
            self.clearAutosaveRecovery()
            onProceed()
        default:
            // Cancel -> do nothing
            break
        }
    }
    
    /// Resets editor state and prompts to open or create a new project
    @MainActor
    public func newProject() {
        checkUnsavedChanges { [weak self] in
            guard let self = self else { return }
            self.cleanupEditorPlayback()
            self.recordedVideoURL = nil
            self.currentProjectURL = nil
            self.projectTitle = "Untitled Project"
            self.currentProjectCreatedAt = nil
            self.videoSegments.removeAll()
            self.audioSegments.removeAll()
            self.zoomKeyframes.removeAll()
            self.telemetryEvents.removeAll()
            self.isDirty = false
            self.clearAutosaveRecovery()
            self.currentView = .launcher
            WindowManager.shared.currentEditorWindow?.orderOut(nil)
            WindowManager.shared.updateWindows()
            self.openProjectDialog()
        }
    }
    
    // MARK: - Background Autosave & Crash Recovery
    
    public func startAutosaveTimer() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performAutosaveRecoverySnapshot()
            }
        }
    }
    
    public func stopAutosaveTimer() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }
    
    @MainActor
    public func performAutosaveRecoverySnapshot() {
        guard isDirty, currentView == .editor, let sourceURL = recordedVideoURL else { return }
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let autosaveDir = appSupport.appendingPathComponent("ClipFocus/Autosave", isDirectory: true)
        let recoveryFile = autosaveDir.appendingPathComponent("recovery.focusproj")
        
        do {
            if !fm.fileExists(atPath: autosaveDir.path) {
                try fm.createDirectory(at: autosaveDir, withIntermediateDirectories: true)
            }
            let project = ClipFocusProject(
                title: self.projectTitle,
                schemaVersion: 1,
                appVersion: "1.0.0",
                createdAt: self.currentProjectCreatedAt ?? Date(),
                updatedAt: Date(),
                duration: self.totalDuration,
                rawVideoFilename: sourceURL.path,
                relativeVideoPath: sourceURL.lastPathComponent,
                videoFileSize: (try? fm.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64,
                embeddedTelemetry: self.telemetryEvents,
                aspectRatio: CanvasAspectRatio(rawValue: self.canvasRatio) ?? .widescreen16x9,
                canvasRatioString: self.canvasRatio,
                exportResolution: self.exportResolution,
                backgroundStyle: CanvasBackgroundStyle(),
                canvasPadding: self.padding,
                canvasCornerRadius: self.roundness,
                canvasShadowRadius: self.shadow,
                canvasShadowOpacity: 0.35,
                activeBackgroundIndex: self.activeBackgroundIndex,
                activeColorIndex: self.activeColorIndex,
                tiltIntensity: self.tiltIntensity,
                disableZoom: self.disableZoom,
                cursorSettings: CursorVisualSettings(),
                webcamSettings: WebcamLayoutSettings(),
                isAudioMuted: self.isAudioMuted,
                audioVolume: self.audioVolume,
                isVideoTrackHidden: self.isVideoTrackHidden,
                isZoomTrackHidden: self.isZoomTrackHidden,
                currentTime: self.currentTime,
                timelineZoomScale: self.timelineZoomScale,
                zoomKeyframes: self.zoomKeyframes,
                subtitles: [],
                videoSegments: self.videoSegments,
                audioSegments: self.audioSegments
            )
            try project.saveAtomic(to: recoveryFile)
            NSLog("[ClipFocus] Autosave recovery snapshot written")
        } catch {
            NSLog("[ClipFocus] Autosave failed: %@", error.localizedDescription)
        }
    }
    
    public func clearAutosaveRecovery() {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let recoveryFile = appSupport.appendingPathComponent("ClipFocus/Autosave/recovery.focusproj")
            try? fm.removeItem(at: recoveryFile)
        }
    }

    // MARK: - Real Video Export with Cut Composition
    
    @MainActor
    public func exportVideo() {
        NSLog("[ClipFocus] exportVideo triggered! recordedVideoURL: %@, segments: %ld", String(describing: recordedVideoURL), videoSegments.count)
        guard !isSavePanelActive && !isExporting else {
            NSLog("[ClipFocus] exportVideo ignored: save panel already active or currently exporting")
            return
        }
        guard let sourceURL = recordedVideoURL else {
            errorMessage = "No recorded video to export. Please record or open a video first."
            return
        }
        guard !videoSegments.isEmpty else {
            errorMessage = "Timeline has no video segments to export."
            return
        }
        
        isSavePanelActive = true
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "ClipFocus_\(sourceURL.deletingPathExtension().lastPathComponent)_Export.mp4"
        savePanel.title = "Export Video"
        
        NSApp.activate(ignoringOtherApps: true)
        let targetWindow = WindowManager.shared.currentEditorWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
        
        if let window = targetWindow, window.attachedSheet == nil {
            window.makeKeyAndOrderFront(nil)
            savePanel.beginSheetModal(for: window) { [weak self] response in
                guard let self = self else { return }
                self.isSavePanelActive = false
                guard response == .OK, let destinationURL = savePanel.url else {
                    NSLog("[ClipFocus] Export cancelled by user in sheet")
                    return
                }
                self.startExportPipeline(destinationURL: destinationURL, sourceURL: sourceURL)
            }
        } else {
            savePanel.begin { [weak self] response in
                guard let self = self else { return }
                self.isSavePanelActive = false
                guard response == .OK, let destinationURL = savePanel.url else {
                    NSLog("[ClipFocus] Export cancelled by user in standalone panel")
                    return
                }
                self.startExportPipeline(destinationURL: destinationURL, sourceURL: sourceURL)
            }
        }
    }
    
    @MainActor
    private func startExportPipeline(destinationURL: URL, sourceURL: URL) {
        NSLog("[ClipFocus] startExportPipeline to destination: %@", destinationURL.path)
        // Disk space check (require at least 50MB)
        if let values = try? destinationURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let available = values.volumeAvailableCapacity, available < 50 * 1024 * 1024 {
            errorMessage = "Insufficient disk space to export video. Please free up space and try again."
            return
        }
        
        try? FileManager.default.removeItem(at: destinationURL)
        
        isExporting = true
        exportProgress = 0.05
        
        Task {
            do {
                let asset = AVURLAsset(url: sourceURL)
                let composition = AVMutableComposition()
                
                // 1. Build Video Track Composition
                if !self.isVideoTrackHidden && !self.videoSegments.isEmpty {
                    if let assetVideoTracks = try? await asset.loadTracks(withMediaType: .video),
                       let assetVideoTrack = assetVideoTracks.first,
                       let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        
                        if let transform = try? await assetVideoTrack.load(.preferredTransform) {
                            compVideoTrack.preferredTransform = transform
                        }
                        
                        for vSeg in self.videoSegments {
                            let sourceRange = CMTimeRange(
                                start: CMTime(seconds: vSeg.sourceStartTime, preferredTimescale: 600),
                                duration: CMTime(seconds: vSeg.duration, preferredTimescale: 600)
                            )
                            let atTime = CMTime(seconds: vSeg.timelineStartTime, preferredTimescale: 600)
                            try compVideoTrack.insertTimeRange(sourceRange, of: assetVideoTrack, at: atTime)
                        }
                    }
                }
                
                // 2. Build Audio Track Composition (Multi-Track Support: System Audio + Microphone)
                if !self.isAudioMuted && !self.audioSegments.isEmpty {
                    if let assetAudioTracks = try? await asset.loadTracks(withMediaType: .audio) {
                        for assetAudioTrack in assetAudioTracks {
                            if let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                                for aSeg in self.audioSegments where !aSeg.isMuted {
                                    let sourceRange = CMTimeRange(
                                        start: CMTime(seconds: aSeg.sourceStartTime, preferredTimescale: 600),
                                        duration: CMTime(seconds: aSeg.duration, preferredTimescale: 600)
                                    )
                                    let atTime = CMTime(seconds: aSeg.timelineStartTime, preferredTimescale: 600)
                                    try compAudioTrack.insertTimeRange(sourceRange, of: assetAudioTrack, at: atTime)
                                }
                            }
                        }
                    }
                }
                
                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                    await MainActor.run {
                        self.isExporting = false
                        self.errorMessage = "Could not initialize video exporter."
                    }
                    return
                }
                
                // 3. Attach Offline Video Compositor (Burns in Zoom, 3D Tilt, Canvas Background & Styling)
                if !self.isVideoTrackHidden && !self.videoSegments.isEmpty {
                    var targetRatio: CGFloat = 16.0 / 9.0
                    switch self.canvasRatio {
                    case "16:9": targetRatio = 16.0 / 9.0
                    case "9:16": targetRatio = 9.0 / 16.0
                    case "1:1": targetRatio = 1.0
                    case "4:3": targetRatio = 4.0 / 3.0
                    case "21:9": targetRatio = 21.0 / 9.0
                    default:
                        if let w = Double(self.customWidth), let h = Double(self.customHeight), h > 0 {
                            targetRatio = CGFloat(w / h)
                        }
                    }
                    
                    var baseDimension: CGFloat = 1080.0
                    switch self.exportResolution {
                    case "4K":
                        baseDimension = 2160.0
                    case "2K":
                        baseDimension = 1440.0
                    case "Auto":
                        if let assetVideoTracks = try? await asset.loadTracks(withMediaType: .video),
                           let firstTrack = assetVideoTracks.first,
                           let naturalSize = try? await firstTrack.load(.naturalSize) {
                            let srcMin = min(naturalSize.width, naturalSize.height)
                            let srcMax = max(naturalSize.width, naturalSize.height)
                            let measured = targetRatio >= 1.0 ? srcMin : srcMax
                            baseDimension = min(2160.0, max(1080.0, CGFloat(Int(measured) & ~1)))
                        } else {
                            baseDimension = 1080.0
                        }
                    default: // "1080p"
                        baseDimension = 1080.0
                    }
                    
                    let renderWidth: CGFloat
                    let renderHeight: CGFloat
                    if targetRatio >= 1.0 {
                        let h = baseDimension
                        let w = CGFloat(Int(round(h * targetRatio)) & ~1)
                        renderWidth = w
                        renderHeight = h
                    } else {
                        let w = baseDimension
                        renderWidth = w
                        renderHeight = CGFloat(Int(round(w / targetRatio)) & ~1)
                    }
                    let renderSize = CGSize(width: renderWidth, height: renderHeight)
                    let canonicalSize = self.canonicalArtboardDimensions()
                    let scaleFactor = renderWidth / canonicalSize.width
                    let scaledPadding = CGFloat(self.padding) * scaleFactor
                    let scaledRoundness = CGFloat(self.roundness) * scaleFactor
                    let scaledShadow = CGFloat(self.shadow) * scaleFactor
                    
                    let compositorConfig = VideoCompositorConfig(
                        renderSize: renderSize,
                        padding: scaledPadding,
                        cornerRadius: scaledRoundness,
                        shadowRadius: scaledShadow,
                        activeBackgroundIndex: self.activeBackgroundIndex,
                        activeColorIndex: self.activeColorIndex,
                        zoomKeyframes: self.zoomKeyframes,
                        telemetryEvents: self.telemetryEvents,
                        tiltIntensity: self.tiltIntensity,
                        disableZoom: self.disableZoom,
                        scaleFactor: scaleFactor
                    )
                    
                    let videoComp = VideoCompositorEngine.shared.buildVideoComposition(
                        for: composition,
                        config: compositorConfig
                    )
                    exportSession.videoComposition = videoComp
                }
                
                await MainActor.run {
                    self.activeExportSession = exportSession
                }
                
                exportSession.outputURL = destinationURL
                let ext = destinationURL.pathExtension.lowercased()
                if ext == "mov" {
                    exportSession.outputFileType = .mov
                } else {
                    exportSession.outputFileType = .mp4
                }
                exportSession.shouldOptimizeForNetworkUse = true
                
                // Async progress monitoring safely dispatching to MainActor
                let progressTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard let self = self, let session = self.activeExportSession else { break }
                        if session.status == .exporting {
                            self.exportProgress = max(0.05, min(0.99, Double(session.progress)))
                        } else {
                            break
                        }
                    }
                }
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    exportSession.exportAsynchronously {
                        continuation.resume()
                    }
                }
                
                progressTask.cancel()
                
                await MainActor.run {
                    self.activeExportSession = nil
                    self.isExporting = false
                    
                    switch exportSession.status {
                    case .completed:
                        self.exportProgress = 1.0
                        self.lastExportedURL = destinationURL
                        self.exportSuccessMessage = "Video exported successfully!"
                        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                    case .cancelled:
                        self.exportProgress = 0.0
                    case .failed:
                        self.exportProgress = 0.0
                        self.errorMessage = "Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")"
                    default:
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 0.0
                    self.errorMessage = "Export failed: \(error.localizedDescription)"
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
        
        // Single Unified Engine Truth: evaluateViewport calculates scale, smooth camera focus (telemetry radar tracking),
        // 3D tilt angles, and pan offsets identically across dynamic playback, scrubbing, paused inspection, and sidebar adjustments.
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
    
    /// Canonical Reference Stage Size:
    /// Provides a deterministic, window-size-independent logical coordinate system for preview and export.
    public func canonicalArtboardDimensions() -> CGSize {
        let targetRatio: CGFloat
        switch self.canvasRatio {
        case "16:9": targetRatio = 16.0 / 9.0
        case "9:16": targetRatio = 9.0 / 16.0
        case "1:1": targetRatio = 1.0
        case "4:3": targetRatio = 4.0 / 3.0
        default: targetRatio = self.videoAspectRatio > 0 ? self.videoAspectRatio : (16.0 / 10.0)
        }
        
        if targetRatio > 1.0 {
            let w: CGFloat = 800.0
            return CGSize(width: w, height: w / targetRatio)
        } else if targetRatio == 1.0 {
            return CGSize(width: 550.0, height: 550.0)
        } else {
            let h: CGFloat = 550.0
            return CGSize(width: h * targetRatio, height: h)
        }
    }
}

/// Snapshot of editor state for Undo / Redo history management
public struct EditorHistorySnapshot: Equatable {
    public var videoSegments: [MediaClipSegment]
    public var audioSegments: [MediaClipSegment]
    public var zoomKeyframes: [ZoomKeyframe]
    public var selectedSegmentID: UUID?
    public var selectedTrackType: TimelineTrackType?
    public var selectedKeyframeID: UUID?
    public var isVideoTrackHidden: Bool
    public var isZoomTrackHidden: Bool
    public var isAudioMuted: Bool
    public var canvasRatio: String
    public var activeBackgroundIndex: Int
    public var activeColorIndex: Int?
    public var padding: Double
    public var inset: Double
    public var roundness: Double
    public var shadow: Double
    public var playbackSpeed: Double
    public var is3DZoomEnabled: Bool
    public var tiltIntensity: Double
    public var selectedSegmentIDs: Set<UUID>? = nil
    public var selectedKeyframeIDs: Set<UUID>? = nil
}

