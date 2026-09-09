import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// Configuration for screen recording session
public struct CaptureSessionConfig: Sendable {
    public var targetDisplayID: CGDirectDisplayID?
    public var captureWidth: Int
    public var captureHeight: Int
    public var frameRate: Int
    public var captureSystemAudio: Bool
    public var captureMicrophoneAudio: Bool
    public var targetMicrophoneName: String?
    public var showHardwareCursor: Bool // We usually hide hardware cursor in raw stream to render styled cursor overlay
    public var sourceRect: CGRect?
    public var targetWindowID: CGWindowID?
    public var excludedWindowIDs: [CGWindowID]

    public init(
        targetDisplayID: CGDirectDisplayID? = nil,
        captureWidth: Int = 1920,
        captureHeight: Int = 1080,
        frameRate: Int = 60,
        captureSystemAudio: Bool = true,
        captureMicrophoneAudio: Bool = true,
        targetMicrophoneName: String? = nil,
        showHardwareCursor: Bool = false,
        sourceRect: CGRect? = nil,
        targetWindowID: CGWindowID? = nil,
        excludedWindowIDs: [CGWindowID] = []
    ) {
        self.targetDisplayID = targetDisplayID
        self.captureWidth = captureWidth
        self.captureHeight = captureHeight
        self.frameRate = frameRate
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophoneAudio = captureMicrophoneAudio
        self.targetMicrophoneName = targetMicrophoneName
        self.showHardwareCursor = showHardwareCursor
        self.sourceRect = sourceRect
        self.targetWindowID = targetWindowID
        self.excludedWindowIDs = excludedWindowIDs
    }
}

/// State of the recording engine
public enum CaptureState: String, Sendable {
    case idle
    case preparing
    case recording
    case paused
    case stopping
}

/// ScreenCaptureKit engine for high-performance macOS screen and audio recording
public final class ScreenCaptureEngine: NSObject, SCStreamDelegate, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    
    public private(set) var state: CaptureState = .idle
    public var isPaused: Bool = false
    private var stream: SCStream?
    private var micCaptureSession: AVCaptureSession?
    private var micAudioOutput: AVCaptureAudioDataOutput?
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var outputFileURL: URL?
    private var sessionStartTime: CMTime?
    private var isSessionStarted: Bool = false
    private var recordedFrameCount: Int = 0
    
    private let processingQueue = DispatchQueue(label: "com.clipfocus.capture.queue", qos: .userInteractive)
    
    public override init() {
        super.init()
    }
    
    private func cleanup() {
        self.state = .idle
        self.stream = nil
        self.micCaptureSession?.stopRunning()
        self.micCaptureSession = nil
        self.micAudioOutput = nil
        self.assetWriter = nil
        self.videoWriterInput = nil
        self.audioWriterInput = nil
        self.sessionStartTime = nil
        self.isSessionStarted = false
        self.recordedFrameCount = 0
    }
    
    /// Prepare and start capturing screen and audio to destination file
    public func startCapture(config: CaptureSessionConfig, outputURL: URL) async throws {
        // If engine is not idle, force-stop any previous session and clean up thoroughly
        if state != .idle {
            NSLog("ScreenCaptureEngine: startCapture called with non-idle state (%@). Forcing reset.", "\(state)")
            if let activeStream = self.stream {
                try? await activeStream.stopCapture()
            }
            if let writer = self.assetWriter, writer.status == .writing {
                writer.cancelWriting()
            }
            cleanup()
        }
        
        cleanup()
        state = .preparing
        self.outputFileURL = outputURL
        
        do {
            // Query shareable display content
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // Identify ClipFocus application and all its floating UI windows to strictly exclude them from the recording
            let myPID = ProcessInfo.processInfo.processIdentifier
            let clipApps = availableContent.applications.filter {
                $0.processID == myPID ||
                $0.applicationName.localizedCaseInsensitiveContains("ClipFocus") ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains("clipfocus")
            }
            let excludedWindows = availableContent.windows.filter {
                config.excludedWindowIDs.contains($0.windowID) ||
                $0.owningApplication?.processID == myPID ||
                ($0.owningApplication?.applicationName.localizedCaseInsensitiveContains("ClipFocus") ?? false) ||
                ($0.owningApplication?.bundleIdentifier.localizedCaseInsensitiveContains("clipfocus") ?? false)
            }
            
            let filter: SCContentFilter
            if let targetWindowID = config.targetWindowID,
               let targetWindow = availableContent.windows.first(where: { $0.windowID == targetWindowID }) {
                filter = SCContentFilter(desktopIndependentWindow: targetWindow)
            } else {
                guard let display = availableContent.displays.first else {
                    cleanup()
                    throw NSError(domain: "ClipFocusCapture", code: 404, userInfo: [NSLocalizedDescriptionKey: "No active display found."])
                }
                
                if !clipApps.isEmpty {
                    filter = SCContentFilter(display: display, excludingApplications: clipApps, exceptingWindows: [])
                } else if #available(macOS 14.0, *) {
                    filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                } else {
                    filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                }
            }
            
            // Determine final recording dimensions
            var finalWidth = config.captureWidth
            var finalHeight = config.captureHeight
            
            let streamConfig = SCStreamConfiguration()
            if let crop = config.sourceRect, crop.width > 0 && crop.height > 0 {
                streamConfig.sourceRect = crop
                finalWidth = Int(crop.width) * 2
                finalHeight = Int(crop.height) * 2
            } else if let targetWindowID = config.targetWindowID,
                      let targetWindow = availableContent.windows.first(where: { $0.windowID == targetWindowID }) {
                finalWidth = Int(targetWindow.frame.width) * 2
                finalHeight = Int(targetWindow.frame.height) * 2
            }
            
            // Make dimensions even for H.264 encoder compatibility
            finalWidth = (finalWidth / 2) * 2
            finalHeight = (finalHeight / 2) * 2
            
            let targetWidth = max(320, finalWidth)
            let targetHeight = max(240, finalHeight)
            
            // Configure stream properties
            streamConfig.width = targetWidth
            streamConfig.height = targetHeight
            streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
            streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
            streamConfig.showsCursor = config.showHardwareCursor
            streamConfig.capturesAudio = config.captureSystemAudio
            streamConfig.sampleRate = 48000
            streamConfig.channelCount = 2
            if #available(macOS 14.0, *) {
                streamConfig.queueDepth = 5
            }
            
            // Setup AVAssetWriter for hardware H.264 / HEVC video encoding
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: targetWidth,
                AVVideoHeightKey: targetHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 15_000_000, // 15 Mbps pristine quality
                    AVVideoExpectedSourceFrameRateKey: config.frameRate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
            }
            
            let shouldCaptureAudio = config.captureSystemAudio || config.captureMicrophoneAudio
            if shouldCaptureAudio {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192000
                ]
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                }
                self.audioWriterInput = audioInput
            }
            
            self.assetWriter = writer
            self.videoWriterInput = videoInput
            
            // Start writer to transition to writing state
            writer.startWriting()
            
            // Setup Microphone Audio Capture if explicitly requested and target name is not None
            if config.captureMicrophoneAudio, let micName = config.targetMicrophoneName, !micName.isEmpty, micName != "None" {
                let micSession = AVCaptureSession()
                micSession.beginConfiguration()
                
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.microphone, .external],
                    mediaType: .audio,
                    position: .unspecified
                )
                let micDevice = discovery.devices.first(where: { $0.localizedName == micName }) ?? AVCaptureDevice.default(for: .audio)
                
                if let device = micDevice, let input = try? AVCaptureDeviceInput(device: device), micSession.canAddInput(input) {
                    micSession.addInput(input)
                    let micOutput = AVCaptureAudioDataOutput()
                    micOutput.setSampleBufferDelegate(self, queue: processingQueue)
                    if micSession.canAddOutput(micOutput) {
                        micSession.addOutput(micOutput)
                        self.micAudioOutput = micOutput
                    }
                }
                micSession.commitConfiguration()
                micSession.startRunning()
                self.micCaptureSession = micSession
            }
            
            // Initialize SCStream
            let scStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
            try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
            if config.captureSystemAudio {
                try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: processingQueue)
            }
            
            self.state = .recording
            try await scStream.startCapture()
            self.stream = scStream
        } catch {
            cleanup()
            throw error
        }
    }
    
    /// Cancel current capture session immediately without writing remaining data
    public func cancelCapture() async {
        state = .stopping
        if let currentStream = stream {
            try? await currentStream.stopCapture()
            self.stream = nil
        }
        if let writer = self.assetWriter, writer.status == .writing {
            writer.cancelWriting()
        }
        if let fileURL = self.outputFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        cleanup()
    }
    
    /// Stop current capture session and finalize movie file
    public func stopCapture() async throws -> URL? {
        guard state == .recording else {
            cleanup()
            return nil
        }
        
        // If recording just started and no frames have arrived yet, wait up to 800ms for initial frames
        if recordedFrameCount == 0 {
            for _ in 0..<8 {
                if recordedFrameCount > 0 { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        
        // Brief grace period so in-flight frames are captured
        try? await Task.sleep(nanoseconds: 150_000_000)
        state = .stopping
        
        if let currentStream = stream {
            try? await currentStream.stopCapture()
            self.stream = nil
        }
        
        NSLog("ScreenCaptureEngine: stopping capture. Frames recorded: %ld, sessionStarted: %@",
              self.recordedFrameCount, self.isSessionStarted ? "YES" : "NO")
        
        return await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    self?.cleanup()
                    continuation.resume(returning: nil)
                    return
                }
                
                // If no frame was ever written or session never started, cancel cleanly
                guard self.isSessionStarted, writer.status == .writing, self.recordedFrameCount > 0 else {
                    NSLog("ScreenCaptureEngine: cancelled writing because sessionStarted=%@, frames=%ld, status=%ld",
                          self.isSessionStarted ? "YES" : "NO", self.recordedFrameCount, writer.status.rawValue)
                    writer.cancelWriting()
                    if let fileURL = self.outputFileURL {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    self.cleanup()
                    continuation.resume(returning: nil)
                    return
                }
                
                self.videoWriterInput?.markAsFinished()
                self.audioWriterInput?.markAsFinished()
                
                writer.finishWriting {
                    let status = writer.status
                    let error = writer.error
                    let finalURL = self.outputFileURL
                    self.cleanup()
                    
                    guard status == .completed, let finalURL = finalURL else {
                        NSLog("ScreenCaptureEngine finishWriting failed with status: %ld, error: %@",
                              status.rawValue, error?.localizedDescription ?? "none")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Verify file has real video data (> 1024 bytes)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path),
                       let size = attrs[.size] as? Int64, size > 1024 {
                        NSLog("ScreenCaptureEngine: successfully finalized video of size %lld bytes", size)
                        continuation.resume(returning: finalURL)
                    } else {
                        NSLog("ScreenCaptureEngine output file is 0 or too small")
                        try? FileManager.default.removeItem(at: finalURL)
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
    // MARK: - SCStreamOutput
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Reject immediately if not actively recording, paused, or invalid buffer data
        guard state == .recording, !isPaused, sampleBuffer.isValid else { return }
        guard let writer = assetWriter, writer.status == .writing else { return }
        
        switch type {
        case .screen:
            // 1. Validate that sampleBuffer has an actual image buffer (CVPixelBuffer).
            // ScreenCaptureKit delivers metadata/status buffers (.started, .blank, etc.) which lack image data.
            // Appending a buffer without an image buffer causes AVAssetWriter to fail immediately!
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            guard CVPixelBufferGetWidth(imageBuffer) > 0 && CVPixelBufferGetHeight(imageBuffer) > 0 else {
                return
            }
            
            // 2. Check frame status in attachments if present
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let firstAttachment = attachments.first,
               let statusRaw = firstAttachment[.status] as? Int,
               let status = SCFrameStatus(rawValue: statusRaw) {
                guard status == .complete else {
                    return
                }
            }
            
            // 3. Always start the AVAssetWriter session with the first VALID video frame
            if !self.isSessionStarted {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                guard pts.isValid && !pts.isIndefinite else { return }
                writer.startSession(atSourceTime: pts)
                self.sessionStartTime = pts
                self.isSessionStarted = true
                NSLog("ScreenCaptureEngine: AVAssetWriter session started at pts: %.3f", pts.seconds)
            }
            
            guard self.isSessionStarted else { return }
            
            if let videoInput = videoWriterInput, videoInput.isReadyForMoreMediaData {
                if videoInput.append(sampleBuffer) {
                    recordedFrameCount += 1
                } else {
                    NSLog("ScreenCaptureEngine: videoInput append failed! Writer status: %ld, error: %@",
                          writer.status.rawValue, writer.error?.localizedDescription ?? "none")
                }
            }
            
        case .audio, .microphone:
            guard self.isSessionStarted, let startTime = self.sessionStartTime else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid && !pts.isIndefinite && pts >= startTime else { return }
            if let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
            
        @unknown default:
            break
        }
    }
    
    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate (Microphone)
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard state == .recording, !isPaused, sampleBuffer.isValid else { return }
        guard let writer = assetWriter, writer.status == .writing else { return }
        guard self.isSessionStarted, let startTime = self.sessionStartTime else { return }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid && !pts.isIndefinite && pts >= startTime else { return }
        
        if let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }
    }
}
