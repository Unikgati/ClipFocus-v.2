import Foundation
import CoreGraphics

/// Types of user input events recorded during a screen session
public enum TelemetryEventType: String, Codable, Sendable {
    case mouseMove = "mouse_move"
    case mouseClick = "mouse_click"
    case mouseUp = "mouse_up"
    case mouseDrag = "mouse_drag"
    case mouseScroll = "mouse_scroll"
    case keyDown = "key_down"
    case windowFocus = "window_focus"
}

/// Standard macOS system cursor shapes recognized during recording
public enum CursorShape: String, Codable, Sendable, CaseIterable {
    case arrow
    case iBeam = "ibeam"
    case pointingHand = "pointing_hand"
    case openHand = "open_hand"
    case closedHand = "closed_hand"
    case resizeLeftRight = "resize_left_right"
    case resizeUpDown = "resize_up_down"
    case crosshair
    case dragCopy = "drag_copy"
    case notAllowed = "not_allowed"
}

/// Mouse button identifier
public enum MouseButtonType: String, Codable, Sendable {
    case left
    case right
    case other
}

/// A timestamped user interaction event captured alongside the screen video
public struct TelemetryEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: TimeInterval // Seconds relative to recording start
    public let type: TelemetryEventType
    public let position: CGPoint? // Normalized (0.0...1.0) or display absolute coordinates
    public let button: MouseButtonType?
    public let clickCount: Int?
    public let modifierFlags: UInt?
    public let keyCharacters: String?
    public let activeWindowBounds: CGRect?
    public let activeAppBundleId: String?
    /// Raw value of `CursorShape` visible at this moment (nil for legacy recordings)
    public let cursorType: String?

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        type: TelemetryEventType,
        position: CGPoint? = nil,
        button: MouseButtonType? = nil,
        clickCount: Int? = nil,
        modifierFlags: UInt? = nil,
        keyCharacters: String? = nil,
        activeWindowBounds: CGRect? = nil,
        activeAppBundleId: String? = nil,
        cursorType: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.position = position
        self.button = button
        self.clickCount = clickCount
        self.modifierFlags = modifierFlags
        self.keyCharacters = keyCharacters
        self.activeWindowBounds = activeWindowBounds
        self.activeAppBundleId = activeAppBundleId
        self.cursorType = cursorType
    }
}
