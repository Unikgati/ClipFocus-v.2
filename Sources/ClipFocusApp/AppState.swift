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
    public var videoSegments: [MediaClipSegment] = []
    public var audioSegments: [MediaClipSegment] = []
    public var selectedSegmentID: UUID? = nil
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
    
    public func selectKeyframe(id: UUID) {
        guard let kf = zoomKeyframes.first(where: { $0.id == id }) else { return }
        selectedKeyframeID = id
        selectedSegmentID = nil
        selectedTrackType = nil
        selectedEffectType = kf.effectType
        selectedTiltPreset = kf.tiltPreset
        customPitch = kf.customPitch
        customYaw = kf.customYaw
        customRoll = kf.customRoll
        positionOffsetX = kf.positionOffsetX
        positionOffsetY = kf.positionOffsetY
        defaultZoomScale = kf.scale
        let seekTime = kf.startTime + min(0.6, kf.duration / 2.0)
        self.currentTime = seekTime
        self.avPlayer?.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        evaluateCurrentZoom()
    }
    
    /// Returns the index of the actively selected zoom keyframe, if any (Pure read-only)
    public func selectedKeyframeIndex() -> Int? {
        if let id = selectedKeyframeID, let idx = zoomKeyframes.firstIndex(where: { $0.id == id }) {
            return idx
        }
        if let idx = zoomKeyframes.firstIndex(where: { currentTime >= $0.startTime && currentTime < ($0.startTime + $0.duration) }) {
            return idx
        }
        if zoomKeyframes.count == 1 {
            return 0
        }
        if let nearest = zoomKeyframes.min(by: { abs($0.startTime - currentTime) < abs($1.startTime - currentTime) }),
           let idx = zoomKeyframes.firstIndex(where: { $0.id == nearest.id }) {
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
    private var playbackDisplayTimer: Timer?
    
    public init() {
        checkPermissions()
        refreshHardwareDevices()
    }
    
    public func checkPermissions() {
        captureManager.checkPermissions()
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraPermission = (camStatus == .authorized)
        
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
                    targetMicrophoneName: self.selectedMic != "None" ? self.selectedMic : nil,
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
    
    public var isAudioMuted: Bool = false
    public var audioWaveformSamples: [Float] = []
    
    public func loadAudioWaveform(from url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
                  let track = audioTracks.first else {
                await MainActor.run {
                    self.audioWaveformSamples = []
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
                
                var rawAmplitudes: [Float] = []
                while reader.status == .reading {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                       let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                        let length = CMBlockBufferGetDataLength(blockBuffer)
                        var data = Data(count: length)
                        data.withUnsafeMutableBytes { bytes in
                            if let base = bytes.baseAddress {
                                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                            }
                        }
                        data.withUnsafeBytes { (int16Ptr: UnsafeRawBufferPointer) in
                            let count = length / 2
                            let buffer = int16Ptr.bindMemory(to: Int16.self)
                            var maxAmp: Float = 0
                            for idx in stride(from: 0, to: count, by: 16) {
                                let amp = abs(Float(buffer[idx])) / 32768.0
                                if amp > maxAmp { maxAmp = amp }
                            }
                            rawAmplitudes.append(maxAmp)
                        }
                    } else {
                        break
                    }
                }
                
                let targetSampleCount = 120
                var condensed: [Float] = []
                if !rawAmplitudes.isEmpty {
                    let bucketSize = max(1, rawAmplitudes.count / targetSampleCount)
                    for i in 0..<targetSampleCount {
                        let startIdx = i * bucketSize
                        let endIdx = min(rawAmplitudes.count, startIdx + bucketSize)
                        if startIdx < rawAmplitudes.count {
                            let slice = rawAmplitudes[startIdx..<endIdx]
                            let avg = slice.reduce(0, +) / Float(slice.count)
                            condensed.append(min(1.0, avg * 3.5 + 0.15))
                        } else {
                            condensed.append(0.15)
                        }
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
        
        // Setup AVPlayer
        let player = AVPlayer(url: url)
        self.avPlayer = player
        self.setVolume(self.audioVolume)
        
        // Asynchronously extract audio waveform for timeline visualization
        self.loadAudioWaveform(from: url)
        
        // Load real asset duration and natural aspect ratio asynchronously
        let asset = AVURLAsset(url: url)
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
        
        // Setup periodic time observer for end-of-playback boundaries
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            if self.isPlaying && !self.isScrubbing && time.seconds >= self.totalDuration {
                self.pauseVideo()
            }
        }
        
        self.currentView = .editor
        self.pauseVideo()
        self.seek(to: 0.0, accurate: true)
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
        
        // 1. Frame / Source Mapping Sync
        if let srcTime = activeSourceTime(for: t) {
            let targetCMTime = CMTime(seconds: srcTime, preferredTimescale: 600)
            let tol: CMTime = accurate ? .zero : CMTime(value: 1, timescale: 30)
            avPlayer?.seek(to: targetCMTime, toleranceBefore: tol, toleranceAfter: tol)
        }
        
        // 2. Audio Track Volume / Mute Sync
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
        if playbackSpeed < 0 {
            playbackSpeed = 1.0
        }
        isPlaying = true
        
        let t = currentTime
        let srcTime = activeSourceTime(for: t)
        if let st = srcTime {
            let targetCM = CMTime(seconds: st, preferredTimescale: 600)
            avPlayer?.seek(to: targetCM, toleranceBefore: CMTime(value: 1, timescale: 30), toleranceAfter: CMTime(value: 1, timescale: 30))
        }
        
        let aSeg = activeAudioSegment(at: t)
        let isMute = isAudioMuted || aSeg == nil || (aSeg?.isMuted ?? false)
        avPlayer?.isMuted = isMute
        avPlayer?.volume = isMute ? 0.0 : Float(audioVolume * (aSeg?.volume ?? 1.0))
        
        if srcTime != nil && playbackSpeed > 0 {
            avPlayer?.rate = Float(playbackSpeed)
        } else {
            avPlayer?.pause()
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
            
            let delta = (1.0 / 60.0) * self.playbackSpeed
            let nextTime = self.currentTime + delta
            
            if nextTime >= self.totalDuration {
                self.currentTime = self.totalDuration
                self.pauseVideo()
                self.syncPlaybackToCurrentTime(accurate: true)
                return
            } else if nextTime <= 0 {
                self.currentTime = 0
                self.pauseVideo()
                self.playbackSpeed = 1.0
                self.syncPlaybackToCurrentTime(accurate: true)
                return
            }
            
            self.currentTime = nextTime
            
            // Media Source Sync (Handles cuts & gaps without constantly interrupting audio)
            if let srcTime = self.activeSourceTime(for: nextTime) {
                if let player = self.avPlayer {
                    let playerSec = player.currentTime().seconds
                    // If player stopped or drifted across a cut boundary (> 0.35s difference), resync seek
                    if abs(playerSec - srcTime) > 0.35 || player.rate == 0 {
                        let targetCM = CMTime(seconds: srcTime, preferredTimescale: 600)
                        player.seek(to: targetCM, toleranceBefore: CMTime(value: 1, timescale: 30), toleranceAfter: CMTime(value: 1, timescale: 30))
                        if self.playbackSpeed > 0 {
                            player.rate = Float(self.playbackSpeed)
                        }
                    }
                }
            } else {
                // Gap / Deleted clip (no video and no audio)
                if self.avPlayer?.rate != 0 {
                    self.avPlayer?.pause()
                }
            }
            
            // Audio Track Volume / Mute Sync
            let aSeg = self.activeAudioSegment(at: nextTime)
            let isMute = self.isAudioMuted || aSeg == nil || (aSeg?.isMuted ?? false)
            if self.avPlayer?.isMuted != isMute {
                self.avPlayer?.isMuted = isMute
            }
            let targetVol = isMute ? 0.0 : Float(self.audioVolume * (aSeg?.volume ?? 1.0))
            if self.avPlayer?.volume != targetVol {
                self.avPlayer?.volume = targetVol
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
            if let srcTime = sourceVideoTime(for: clamped) {
                let targetCMTime = CMTime(seconds: srcTime, preferredTimescale: 600)
                let tol = CMTime(value: 1, timescale: 30)
                avPlayer?.seek(to: targetCMTime, toleranceBefore: tol, toleranceAfter: tol)
            }
        }
    }
    
    public func endHoverPreview() {
        guard !isPlaying && !isScrubbing else { return }
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func selectSegment(id: UUID, trackType: TimelineTrackType) {
        self.selectedSegmentID = id
        self.selectedTrackType = trackType
        self.selectedKeyframeID = nil
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
            tiltIntensity: self.tiltIntensity
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
        self.selectedSegmentID = s.selectedSegmentID
        self.selectedTrackType = s.selectedTrackType
        self.selectedKeyframeID = s.selectedKeyframeID
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
        
        evaluateCurrentZoom()
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    public func clearSelection() {
        self.selectedSegmentID = nil
        self.selectedTrackType = nil
        self.selectedKeyframeID = nil
    }
    
    public func deleteSelected() {
        recordUndoState()
        if let segID = selectedSegmentID, let type = selectedTrackType {
            switch type {
            case .video:
                videoSegments.removeAll { $0.id == segID }
            case .audio:
                audioSegments.removeAll { $0.id == segID }
            case .zoom:
                zoomKeyframes.removeAll { $0.id == segID }
            }
            selectedSegmentID = nil
            selectedTrackType = nil
        } else if let kfID = selectedKeyframeID {
            zoomKeyframes.removeAll { $0.id == kfID }
            selectedKeyframeID = nil
        }
        evaluateCurrentZoom()
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func deleteVideoSegment(id: UUID) {
        recordUndoState()
        videoSegments.removeAll { $0.id == id }
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func deleteAudioSegment(id: UUID) {
        recordUndoState()
        audioSegments.removeAll { $0.id == id }
        syncPlaybackToCurrentTime(accurate: true)
    }
    
    public func splitAtCurrentTime() {
        let t = currentTime
        var hasSplitAnything = false
        
        // 1. If a specific video clip is selected, split it; otherwise split any video clip intersecting playhead
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
        
        // 2. If a specific audio clip is selected, split it; otherwise split any audio clip intersecting playhead
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
        
        // 3. If a zoom keyframe intersects playhead, split it
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
    
    // MARK: - Real Video Export with Cut Composition
    
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
                            try? compVideoTrack.insertTimeRange(sourceRange, of: assetVideoTrack, at: atTime)
                        }
                    }
                }
                
                // 2. Build Audio Track Composition
                if !self.isAudioMuted && !self.audioSegments.isEmpty {
                    if let assetAudioTracks = try? await asset.loadTracks(withMediaType: .audio),
                       let assetAudioTrack = assetAudioTracks.first,
                       let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        
                        for aSeg in self.audioSegments where !aSeg.isMuted {
                            let sourceRange = CMTimeRange(
                                start: CMTime(seconds: aSeg.sourceStartTime, preferredTimescale: 600),
                                duration: CMTime(seconds: aSeg.duration, preferredTimescale: 600)
                            )
                            let atTime = CMTime(seconds: aSeg.timelineStartTime, preferredTimescale: 600)
                            try? compAudioTrack.insertTimeRange(sourceRange, of: assetAudioTrack, at: atTime)
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
        } else if let idx = selectedKeyframeIndex() {
            // Paused with a keyframe selected: reflect that keyframe's live values & 3D angles immediately
            let kf = zoomKeyframes[idx]
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
}

