import Foundation
import CoreGraphics

/// Types of user input events recorded during a screen session
public enum TelemetryEventType: String, Codable, Sendable {
    case mouseMove = "mouse_move"
    case mouseClick = "mouse_click"
    case mouseDrag = "mouse_drag"
    case mouseScroll = "mouse_scroll"
    case keyDown = "key_down"
    case windowFocus = "window_focus"
}

/// Mouse button identifier
public enum MouseButtonType: String, Codable, Sendable {
    case left
    case right
    case other
}

/// Visual cursor pointer shape
public enum CursorType: String, Codable, Sendable {
    case arrow = "arrow"
    case pointingHand = "pointing_hand"
    case iBeam = "ibeam"
    case openHand = "open_hand"
    case closedHand = "closed_hand"
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
    public let cursorType: CursorType?

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
        cursorType: CursorType? = nil
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
