import Foundation
import CoreGraphics
import AppKit

/// Protocol to receive telemetry updates as they occur during recording
public protocol CursorTrackerDelegate: AnyObject, Sendable {
    func cursorTrackerDidCapture(event: TelemetryEvent)
}

/// Global input monitor capturing cursor coordinates, mouse clicks, and keystrokes
public final class CursorTracker: @unchecked Sendable {
    
    private var isTracking = false
    public private(set) var isPaused = false
    private var totalPausedDuration: TimeInterval = 0.0
    private var recordingStartTime: Date?
    private var globalMonitors: [Any] = []
    private var pollingTimer: Timer?
    private var lastSampledPosition: CGPoint?
    private var lastRecordedTimestamp: TimeInterval = 0.0
    public weak var delegate: CursorTrackerDelegate?
    
    public private(set) var recordedEvents: [TelemetryEvent] = []
    private let queue = DispatchQueue(label: "com.clipfocus.telemetry.queue", qos: .userInteractive)
    
    public init() {}
    
    public func pauseTracking() {
        queue.sync {
            self.isPaused = true
        }
    }
    
    public func resumeTracking(pausedDuration: TimeInterval) {
        queue.sync {
            self.totalPausedDuration += pausedDuration
            self.isPaused = false
        }
    }
    
    /// Start recording telemetry events
    public func startTracking() {
        queue.sync {
            self.recordedEvents.removeAll()
            self.recordingStartTime = Date()
            self.totalPausedDuration = 0.0
            self.isPaused = false
            self.isTracking = true
            self.lastSampledPosition = nil
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. High-frequency 60Hz hardware cursor polling (100% reliable across all apps without Accessibility privileges)
            self.pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.sampleHardwareCursor()
            }
            if let timer = self.pollingTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
            
            // 2. Event monitor for left and right mouse clicks
            let clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handleMouseEvent(event, type: .mouseClick)
            }
            if let clickMonitor = clickMonitor {
                self.globalMonitors.append(clickMonitor)
            }
            
            // 3. Event monitor for mouse dragging & moving
            let dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged, .mouseMoved]) { [weak self] event in
                self?.handleMouseEvent(event, type: (event.type == .mouseMoved) ? .mouseMove : .mouseDrag)
            }
            if let dragMonitor = dragMonitor {
                self.globalMonitors.append(dragMonitor)
            }
            
            // 4. Event monitor for keystrokes (shortcut pills & typing detection)
            let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handleKeyEvent(event)
            }
            if let keyMonitor = keyMonitor {
                self.globalMonitors.append(keyMonitor)
            }
        }
    }
    
    /// Sample global hardware cursor location at 60Hz
    private func sampleHardwareCursor() {
        guard isTracking, !isPaused, let startTime = recordingStartTime else { return }
        let rawElapsed = Date().timeIntervalSince(startTime)
        let timestamp = max(0.0, rawElapsed - totalPausedDuration)
        
        let screenPoint = NSEvent.mouseLocation
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let frame = primaryScreen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        
        let normalizedX = max(0.0, min(1.0, (screenPoint.x - frame.origin.x) / frame.width))
        let normalizedY = max(0.0, min(1.0, (frame.origin.y + frame.height - screenPoint.y) / frame.height))
        let position = CGPoint(x: normalizedX, y: normalizedY)
        
        // Deduplicate micro jitter if stationary, but emit a stationary anchor event every 0.10s
        if let last = lastSampledPosition {
            let dx = abs(last.x - position.x)
            let dy = abs(last.y - position.y)
            if dx < 0.001 && dy < 0.001 && (timestamp - lastRecordedTimestamp) < 0.10 {
                return
            }
        }
        self.lastSampledPosition = position
        self.lastRecordedTimestamp = timestamp
        
        var resolvedCursor: CursorType = .arrow
        if NSEvent.pressedMouseButtons != 0 {
            resolvedCursor = .closedHand
        } else {
            let cursor = NSCursor.current
            if cursor == NSCursor.iBeam {
                resolvedCursor = .iBeam
            } else if cursor == NSCursor.pointingHand {
                resolvedCursor = .pointingHand
            } else if cursor == NSCursor.openHand {
                resolvedCursor = .openHand
            } else if cursor == NSCursor.closedHand {
                resolvedCursor = .closedHand
            }
        }
        
        let telemetryEvent = TelemetryEvent(
            timestamp: timestamp,
            type: .mouseMove,
            position: position,
            cursorType: resolvedCursor
        )
        recordEvent(telemetryEvent)
    }
    
    /// Stop tracking and return all collected events
    public func stopTracking() -> [TelemetryEvent] {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollingTimer?.invalidate()
            self.pollingTimer = nil
            for monitor in self.globalMonitors {
                NSEvent.removeMonitor(monitor)
            }
            self.globalMonitors.removeAll()
        }
        
        return queue.sync {
            self.isTracking = false
            return self.recordedEvents
        }
    }
    
    /// Record a synthetic or captured event directly (used also for simulated sessions and unit testing)
    public func recordEvent(_ event: TelemetryEvent) {
        queue.sync {
            self.recordedEvents.append(event)
        }
        delegate?.cursorTrackerDidCapture(event: event)
    }
    
    // MARK: - Private Handlers
    
    private func handleMouseEvent(_ event: NSEvent, type: TelemetryEventType) {
        guard isTracking, !isPaused, let startTime = recordingStartTime else { return }
        let rawElapsed = Date().timeIntervalSince(startTime)
        let timestamp = max(0.0, rawElapsed - totalPausedDuration)
        
        let screenPoint = NSEvent.mouseLocation
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let frame = primaryScreen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        
        // Convert to normalized coordinates (0.0 to 1.0) with (0,0) as top-left
        let normalizedX = max(0.0, min(1.0, (screenPoint.x - frame.origin.x) / frame.width))
        let normalizedY = max(0.0, min(1.0, (frame.origin.y + frame.height - screenPoint.y) / frame.height))
        let position = CGPoint(x: normalizedX, y: normalizedY)
        
        let button: MouseButtonType = (event.type == .rightMouseDown || event.type == .rightMouseDragged) ? .right : .left
        
        var cursorType: CursorType = (type == .mouseDrag) ? .closedHand : .arrow
        if type != .mouseDrag {
            let cursor = NSCursor.current
            if cursor == NSCursor.iBeam {
                cursorType = .iBeam
            } else if cursor == NSCursor.pointingHand {
                cursorType = .pointingHand
            } else if cursor == NSCursor.openHand {
                cursorType = .openHand
            } else if cursor == NSCursor.closedHand {
                cursorType = .closedHand
            }
        }
        
        let telemetryEvent = TelemetryEvent(
            timestamp: timestamp,
            type: type,
            position: position,
            button: button,
            clickCount: event.clickCount,
            modifierFlags: event.modifierFlags.rawValue,
            cursorType: cursorType
        )
        
        recordEvent(telemetryEvent)
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        guard isTracking, !isPaused, let startTime = recordingStartTime else { return }
        let rawElapsed = Date().timeIntervalSince(startTime)
        let timestamp = max(0.0, rawElapsed - totalPausedDuration)
        
        let screenPoint = NSEvent.mouseLocation
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let frame = primaryScreen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let normalizedX = max(0.0, min(1.0, (screenPoint.x - frame.origin.x) / frame.width))
        let normalizedY = max(0.0, min(1.0, (frame.origin.y + frame.height - screenPoint.y) / frame.height))
        
        let telemetryEvent = TelemetryEvent(
            timestamp: timestamp,
            type: .keyDown,
            position: CGPoint(x: normalizedX, y: normalizedY),
            modifierFlags: event.modifierFlags.rawValue,
            keyCharacters: event.charactersIgnoringModifiers
        )
        
        recordEvent(telemetryEvent)
    }
}
