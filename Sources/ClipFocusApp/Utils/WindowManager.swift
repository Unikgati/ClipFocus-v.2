import SwiftUI
import AppKit
import ScreenCaptureKit

/// Dedicated NSHostingView that processes native mouse cursor and drag scaling for Custom Crop Mode
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    weak var appState: AppState?
    
    public enum DragHandle {
        case none
        case body
        case topLeft, topRight, bottomLeft, bottomRight
        case topEdge, bottomEdge, leftEdge, rightEdge
        
        var cursor: NSCursor {
            switch self {
            case .none:
                return NSCursor.arrow
            case .body:
                return NSCursor.openHand
            case .topLeft, .bottomRight:
                return CustomCursorHelper.nwseCursor
            case .topRight, .bottomLeft:
                return CustomCursorHelper.neswCursor
            case .topEdge, .bottomEdge:
                return NSCursor.resizeUpDown
            case .leftEdge, .rightEdge:
                return NSCursor.resizeLeftRight
            }
        }
    }
    
    private var activeDragHandle: DragHandle = .none
    private var dragStartMouse: CGPoint = .zero
    private var dragStartRect: CGRect = .zero
    private var trackingAreaRef: NSTrackingArea?
    
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingAreaRef = area
    }
    
    private func hitTestHandle(at pt: CGPoint, crop: CGRect) -> DragHandle {
        let cornerHitRadius: CGFloat = 16.0
        let edgeHitThickness: CGFloat = 8.0
        
        // 1. Check 4 Corners
        if hypot(pt.x - crop.minX, pt.y - crop.minY) <= cornerHitRadius { return .topLeft }
        if hypot(pt.x - crop.maxX, pt.y - crop.minY) <= cornerHitRadius { return .topRight }
        if hypot(pt.x - crop.minX, pt.y - crop.maxY) <= cornerHitRadius { return .bottomLeft }
        if hypot(pt.x - crop.maxX, pt.y - crop.maxY) <= cornerHitRadius { return .bottomRight }
        
        // 2. Check 4 Edges
        if pt.x >= crop.minX && pt.x <= crop.maxX {
            if abs(pt.y - crop.minY) <= edgeHitThickness { return .topEdge }
            if abs(pt.y - crop.maxY) <= edgeHitThickness { return .bottomEdge }
        }
        if pt.y >= crop.minY && pt.y <= crop.maxY {
            if abs(pt.x - crop.minX) <= edgeHitThickness { return .leftEdge }
            if abs(pt.x - crop.maxX) <= edgeHitThickness { return .rightEdge }
        }
        
        // 3. Check Body
        if crop.contains(pt) {
            return .body
        }
        
        return .none
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard let appState = self.appState, appState.selectedMode == .custom, !appState.isCountingDown else {
            super.mouseMoved(with: event)
            return
        }
        
        let mouseInWindow = event.locationInWindow
        let pt = CGPoint(x: mouseInWindow.x, y: bounds.height - mouseInWindow.y)
        
        let handle = hitTestHandle(at: pt, crop: appState.customCropRect)
        handle.cursor.set()
    }
    
    override func cursorUpdate(with event: NSEvent) {
        guard let appState = self.appState, appState.selectedMode == .custom, !appState.isCountingDown else {
            super.cursorUpdate(with: event)
            return
        }
        
        let mouseInWindow = event.locationInWindow
        let pt = CGPoint(x: mouseInWindow.x, y: bounds.height - mouseInWindow.y)
        
        let handle = hitTestHandle(at: pt, crop: appState.customCropRect)
        handle.cursor.set()
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let appState = self.appState, appState.selectedMode == .custom, !appState.isCountingDown else {
            super.mouseDown(with: event)
            return
        }
        
        let mouseInWindow = event.locationInWindow
        let pt = CGPoint(x: mouseInWindow.x, y: bounds.height - mouseInWindow.y)
        
        let handle = hitTestHandle(at: pt, crop: appState.customCropRect)
        if handle != .none {
            activeDragHandle = handle
            dragStartMouse = pt
            dragStartRect = appState.customCropRect
            if handle == .body {
                NSCursor.closedHand.set()
            } else {
                handle.cursor.set()
            }
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let appState = self.appState, appState.selectedMode == .custom, activeDragHandle != .none else {
            super.mouseDragged(with: event)
            return
        }
        
        let mouseInWindow = event.locationInWindow
        let pt = CGPoint(x: mouseInWindow.x, y: bounds.height - mouseInWindow.y)
        
        let deltaX = pt.x - dragStartMouse.x
        let deltaY = pt.y - dragStartMouse.y
        let start = dragStartRect
        let minW: CGFloat = 160
        let minH: CGFloat = 100
        let maxW = bounds.width
        let maxH = bounds.height
        
        switch activeDragHandle {
        case .body:
            NSCursor.closedHand.set()
            var newX = start.origin.x + deltaX
            var newY = start.origin.y + deltaY
            newX = max(0, min(maxW - start.width, newX))
            newY = max(0, min(maxH - start.height, newY))
            appState.customCropRect.origin = CGPoint(x: newX, y: newY)
            
        case .topLeft:
            activeDragHandle.cursor.set()
            let newX = min(start.maxX - minW, max(0, start.minX + deltaX))
            let newY = min(start.maxY - minH, max(0, start.minY + deltaY))
            appState.customCropRect = CGRect(x: newX, y: newY, width: start.maxX - newX, height: start.maxY - newY)
            
        case .topRight:
            activeDragHandle.cursor.set()
            let newY = min(start.maxY - minH, max(0, start.minY + deltaY))
            let newW = max(minW, min(maxW - start.minX, start.width + deltaX))
            appState.customCropRect = CGRect(x: start.minX, y: newY, width: newW, height: start.maxY - newY)
            
        case .bottomLeft:
            activeDragHandle.cursor.set()
            let newX = min(start.maxX - minW, max(0, start.minX + deltaX))
            let newH = max(minH, min(maxH - start.minY, start.height + deltaY))
            appState.customCropRect = CGRect(x: newX, y: start.minY, width: start.maxX - newX, height: newH)
            
        case .bottomRight:
            activeDragHandle.cursor.set()
            let newW = max(minW, min(maxW - start.minX, start.width + deltaX))
            let newH = max(minH, min(maxH - start.minY, start.height + deltaY))
            appState.customCropRect = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
            
        case .topEdge:
            activeDragHandle.cursor.set()
            let newY = min(start.maxY - minH, max(0, start.minY + deltaY))
            appState.customCropRect = CGRect(x: start.minX, y: newY, width: start.width, height: start.maxY - newY)
            
        case .bottomEdge:
            activeDragHandle.cursor.set()
            let newH = max(minH, min(maxH - start.minY, start.height + deltaY))
            appState.customCropRect = CGRect(x: start.minX, y: start.minY, width: start.width, height: newH)
            
        case .leftEdge:
            activeDragHandle.cursor.set()
            let newX = min(start.maxX - minW, max(0, start.minX + deltaX))
            appState.customCropRect = CGRect(x: newX, y: start.minY, width: start.maxX - newX, height: start.height)
            
        case .rightEdge:
            activeDragHandle.cursor.set()
            let newW = max(minW, min(maxW - start.minX, start.width + deltaX))
            appState.customCropRect = CGRect(x: start.minX, y: start.minY, width: newW, height: start.height)
            
        case .none:
            break
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if activeDragHandle != .none {
            activeDragHandle = .none
            if let appState = self.appState, appState.selectedMode == .custom {
                let mouseInWindow = event.locationInWindow
                let pt = CGPoint(x: mouseInWindow.x, y: bounds.height - mouseInWindow.y)
                let handle = hitTestHandle(at: pt, crop: appState.customCropRect)
                handle.cursor.set()
            } else {
                NSCursor.arrow.set()
            }
        } else {
            super.mouseUp(with: event)
        }
    }
}

/// Dedicated borderless floating panel for overlays (Floating Control Bar & Recording Pill)
public final class FloatingPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 10)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
    }
}

/// Central Window Manager providing 100% production-ready, dedicated window lifecycles for ClipFocus
@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()
    
    public var appState: AppState?
    
    private var launcherWindow: NSWindow?
    private var floatingBarPanel: FloatingPanel?
    private var recordingPillPanel: FloatingPanel?
    private var editorWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var areaOverlayPanel: NSPanel?
    
    public var currentEditorWindow: NSWindow? {
        return editorWindow
    }
    
    // Window Mode Hover & Selection Tracking
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var windowHoverTimer: Timer?
    private var cachedUserWindows: [SCWindow] = []
    
    // ESC Key Monitoring
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    
    public func start(with appState: AppState) {
        self.appState = appState
        setupLauncherWindow()
        setupFloatingBarPanel()
        setupRecordingPillPanel()
        setupEditorWindow()
        setupPermissionsWindow()
        setupAreaOverlayPanel()
        setupEscapeKeyMonitoring()
        
        observeAppState()
        setupScreenChangeMonitoring()
        updateWindows()
    }
    
    private func setupScreenChangeMonitoring() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let appState = self.appState else { return }
                appState.refreshAvailableDisplays()
                self.repositionAreaOverlay()
                self.repositionFloatingBar()
            }
        }
    }
    
    public func setupEscapeKeyMonitoring() {
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // ESC key
                    Task { @MainActor in
                        self?.handleEscapeKey()
                    }
                    return nil
                }
                return event
            }
        }
        
        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // ESC key
                    Task { @MainActor in
                        self?.handleEscapeKey()
                    }
                }
            }
        }
    }
    
    @MainActor
    public func handleEscapeKey() {
        guard let appState = self.appState else { return }
        
        if appState.isCountingDown {
            appState.isCountingDown = false
            appState.closeControlBar()
        } else if appState.currentView == .recording {
            appState.discardRecording()
        } else if appState.currentView == .floatingControlBar || appState.selectedMode != nil {
            appState.closeControlBar()
        }
    }
    
    private func observeAppState() {
        guard let appState = self.appState else { return }
        withObservationTracking {
            _ = appState.currentView
            _ = appState.showPermissionsWindow
            _ = appState.selectedMode
            _ = appState.isCountingDown
            _ = appState.selectedCamera
            _ = appState.selectedMic
            _ = appState.selectedAudio
            _ = appState.selectedDisplayID
            _ = appState.selectedWindowID
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateWindows()
                self?.repositionFloatingBar()
                self?.repositionAreaOverlay()
                self?.observeAppState()
            }
        }
    }
    
    public func updateWindows() {
        guard let appState = self.appState else { return }
        
        switch appState.currentView {
        case .launcher:
            stopWindowModeTracking()
            areaOverlayPanel?.orderOut(nil)
            floatingBarPanel?.orderOut(nil)
            recordingPillPanel?.orderOut(nil)
            editorWindow?.orderOut(nil)
            
            if let window = launcherWindow {
                window.alphaValue = 1.0
                window.ignoresMouseEvents = false
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
            
        case .floatingControlBar:
            recordingPillPanel?.orderOut(nil)
            editorWindow?.orderOut(nil)
            
            // Keep launcherWindow open but 100% invisible to maintain SwiftUI app lifecycle
            launcherWindow?.alphaValue = 0.0
            launcherWindow?.ignoresMouseEvents = true
            
            // 1. Show area overlay if mode is selected and not counting down
            if appState.selectedMode != nil && !appState.isCountingDown {
                repositionAreaOverlay()
                // Custom mode needs mouse interaction for dragging crop handles.
                // FullScreen and Window modes use passive visual outlines without blocking clicks.
                if appState.selectedMode == .custom {
                    areaOverlayPanel?.ignoresMouseEvents = false
                } else {
                    areaOverlayPanel?.ignoresMouseEvents = true
                }
                areaOverlayPanel?.orderFrontRegardless()
            } else {
                areaOverlayPanel?.orderOut(nil)
            }
            
            // 2. Show floating control bar on top
            if let panel = floatingBarPanel {
                repositionFloatingBar()
                panel.invalidateShadow()
                panel.makeKeyAndOrderFront(nil)
                panel.orderFrontRegardless()
            }
            
            // 3. Start or stop Window Mode hover tracking
            if appState.selectedMode == .window && !appState.isCountingDown {
                startWindowModeTracking()
            } else {
                stopWindowModeTracking()
            }
            
        case .recording:
            stopWindowModeTracking()
            areaOverlayPanel?.orderOut(nil)
            launcherWindow?.alphaValue = 0.0
            launcherWindow?.ignoresMouseEvents = true
            floatingBarPanel?.orderOut(nil)
            editorWindow?.orderOut(nil)
            
            if let pill = recordingPillPanel {
                repositionRecordingPill()
                pill.invalidateShadow()
                pill.orderFrontRegardless()
            }
            
        case .editor:
            stopWindowModeTracking()
            areaOverlayPanel?.orderOut(nil)
            launcherWindow?.alphaValue = 0.0
            launcherWindow?.ignoresMouseEvents = true
            floatingBarPanel?.orderOut(nil)
            recordingPillPanel?.orderOut(nil)
            
            if let window = editorWindow {
                window.title = "\(appState.projectTitle) — ClipFocus"
                window.isDocumentEdited = appState.isDirty
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        
        // Handle Permissions Window (Takes key focus over the underlying view when requested)
        if appState.showPermissionsWindow {
            if permissionsWindow == nil {
                setupPermissionsWindow()
            }
            permissionsWindow?.center()
            permissionsWindow?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            permissionsWindow?.orderOut(nil)
        }
    }
    
    // MARK: - Window Configurations
    
    private func setupLauncherWindow() {
        guard let appState = self.appState else { return }
        let rect = NSRect(x: 0, y: 0, width: 706, height: 215)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: LauncherModalView(appState: appState).preferredColorScheme(.dark))
        window.contentView = hostingView
        window.center()
        self.launcherWindow = window
    }
    
    private func setupFloatingBarPanel() {
        guard let appState = self.appState else { return }
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 46))
        
        let hostingView = NSHostingView(rootView: FloatingControlBarView(appState: appState).preferredColorScheme(.dark))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        panel.orderOut(nil)
        self.floatingBarPanel = panel
    }
    
    private func setupRecordingPillPanel() {
        guard let appState = self.appState else { return }
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 46))
        
        let pillView = RecordingPillWrapper(appState: appState)
        let hostingView = NSHostingView(rootView: pillView.preferredColorScheme(.dark))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        panel.orderOut(nil)
        self.recordingPillPanel = panel
    }
    
    private func setupEditorWindow() {
        guard let appState = self.appState else { return }
        let rect = NSRect(x: 0, y: 0, width: 1150, height: 740)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: EditorStudioView(appState: appState).preferredColorScheme(.dark))
        window.contentView = hostingView
        window.orderOut(nil)
        self.editorWindow = window
    }
    
    private func setupPermissionsWindow() {
        guard let appState = self.appState else { return }
        let rect = NSRect(x: 0, y: 0, width: 620, height: 460)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        
        let hostingView = NSHostingView(
            rootView: PermissionsModalView(appState: appState) { [weak self] in
                self?.appState?.showPermissionsWindow = false
            }.preferredColorScheme(.dark)
        )
        window.contentView = hostingView
        window.center()
        self.permissionsWindow = window
    }
    
    public static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        return NSScreen.screens.first(where: { screen in
            let rawNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            let id = rawNum ?? (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            return id == displayID
        })
    }
    
    public func repositionFloatingBar() {
        guard let panel = floatingBarPanel, let hostingView = panel.contentView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        
        let targetScreen: NSScreen?
        if let targetDisplayID = appState?.selectedDisplayID {
            targetScreen = WindowManager.screen(for: targetDisplayID)
        } else {
            targetScreen = nil
        }
        let screen = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1440, height: 900)
        let barWidth: CGFloat = max(340, ceil(fitting.width))
        let barHeight: CGFloat = 46
        let rect = NSRect(
            x: screen.midX - (barWidth / 2),
            y: screen.minY + 60,
            width: barWidth,
            height: barHeight
        )
        panel.setFrame(rect, display: true, animate: false)
    }
    
    private func repositionRecordingPill() {
        guard let panel = recordingPillPanel else { return }
        let targetScreen: NSScreen?
        if let targetDisplayID = appState?.selectedDisplayID {
            targetScreen = WindowManager.screen(for: targetDisplayID)
        } else {
            targetScreen = nil
        }
        let screen = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1440, height: 900)
        let pillWidth: CGFloat = (appState?.isFinalizingRecording == true) ? 310 : (appState?.autoStopDuration != nil ? 340 : 290)
        let pillHeight: CGFloat = 46
        let rect = NSRect(
            x: screen.midX - (pillWidth / 2),
            y: screen.minY + 60,
            width: pillWidth,
            height: pillHeight
        )
        panel.setFrame(rect, display: true)
    }
    
    private func setupAreaOverlayPanel() {
        guard let appState = self.appState else { return }
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = NSPanel(
            contentRect: screen,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        
        let hostingView = OverlayHostingView(rootView: RecordingAreaOverlayView(appState: appState).preferredColorScheme(.dark))
        hostingView.appState = appState
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        panel.orderOut(nil)
        self.areaOverlayPanel = panel
    }
    
    public func repositionAreaOverlay() {
        guard let panel = areaOverlayPanel else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 1080
        
        // 1. If in FullScreen mode, place border indicator directly on the selected target display (e.g. external monitor)
        if appState?.selectedMode == .fullScreen, let targetDisplayID = appState?.selectedDisplayID {
            if let matchedScreen = WindowManager.screen(for: targetDisplayID) {
                if panel.frame != matchedScreen.frame {
                    panel.setFrame(matchedScreen.frame, display: true)
                }
                return
            }
        }
        
        // 2. If in Window mode and we have a selected window, align panel with the screen containing that window
        if appState?.selectedMode == .window, let targetFrame = appState?.selectedWindowFrame ?? appState?.hoveredWindowFrame {
            if let matchedScreen = NSScreen.screens.first(where: { screen in
                let qX = screen.frame.origin.x
                let qY = primaryH - (screen.frame.origin.y + screen.frame.height)
                let screenQRect = CGRect(x: qX, y: qY, width: screen.frame.width, height: screen.frame.height)
                return screenQRect.intersects(targetFrame)
            }) {
                if panel.frame != matchedScreen.frame {
                    panel.setFrame(matchedScreen.frame, display: true)
                }
                return
            }
        }
        
        // 3. If in Custom mode and target display is chosen
        if appState?.selectedMode == .custom, let targetDisplayID = appState?.selectedDisplayID {
            if let matchedScreen = WindowManager.screen(for: targetDisplayID) {
                if panel.frame != matchedScreen.frame {
                    panel.setFrame(matchedScreen.frame, display: true)
                }
                return
            }
        }
        
        // Fallback: Screen containing mouse location or main screen
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main ?? NSScreen.screens.first
        if let screen = targetScreen, panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: true)
        }
    }
    
    public func allClipFocusWindowIDs() -> [CGWindowID] {
        var ids: [CGWindowID] = []
        if let w = launcherWindow { ids.append(CGWindowID(w.windowNumber)) }
        if let p = floatingBarPanel { ids.append(CGWindowID(p.windowNumber)) }
        if let r = recordingPillPanel { ids.append(CGWindowID(r.windowNumber)) }
        if let e = editorWindow { ids.append(CGWindowID(e.windowNumber)) }
        if let pm = permissionsWindow { ids.append(CGWindowID(pm.windowNumber)) }
        if let ao = areaOverlayPanel { ids.append(CGWindowID(ao.windowNumber)) }
        return ids
    }
    
    // MARK: - Window Hover & Selection Tracking for Window Mode
    
    private func startWindowModeTracking() {
        guard globalMouseMonitor == nil else { return }
        
        refreshCachedWindows()
        
        windowHoverTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCachedWindows()
            }
        }
        
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleTrackedMouseEvent(event)
            }
        }
        
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            self?.handleTrackedMouseEvent(event)
            return event
        }
    }
    
    private func stopWindowModeTracking() {
        if let g = globalMouseMonitor {
            NSEvent.removeMonitor(g)
            globalMouseMonitor = nil
        }
        if let l = localMouseMonitor {
            NSEvent.removeMonitor(l)
            localMouseMonitor = nil
        }
        windowHoverTimer?.invalidate()
        windowHoverTimer = nil
        cachedUserWindows.removeAll()
    }
    
    private func handleTrackedMouseEvent(_ event: NSEvent) {
        guard let appState = self.appState, appState.selectedMode == .window, !appState.isCountingDown else { return }
        
        let mouseLoc = NSEvent.mouseLocation
        let primaryScreen = NSScreen.screens.first
        let primaryH = primaryScreen?.frame.height ?? 1080
        let pt = CGPoint(x: mouseLoc.x, y: primaryH - mouseLoc.y)
        
        // If mouse is inside the floating control bar, preserve active selection and do not re-hover
        if let floatingFrame = floatingBarPanel?.frame, floatingFrame.contains(mouseLoc) {
            return
        }
        
        if event.type == .mouseMoved {
            if let match = cachedUserWindows.first(where: { $0.frame.contains(pt) }) {
                if appState.hoveredWindowID != match.windowID {
                    appState.hoveredWindowID = match.windowID
                    appState.hoveredWindowFrame = match.frame
                    appState.hoveredWindowName = match.owningApplication?.applicationName ?? match.title
                    appState.selectedWindowID = match.windowID
                    appState.selectedWindowFrame = match.frame
                    appState.selectedWindowName = match.owningApplication?.applicationName ?? match.title
                    repositionAreaOverlay()
                }
            } else {
                appState.hoveredWindowID = nil
                appState.hoveredWindowFrame = nil
            }
        } else if event.type == .leftMouseDown {
            if let match = cachedUserWindows.first(where: { $0.frame.contains(pt) }) {
                appState.selectedWindowID = match.windowID
                appState.selectedWindowFrame = match.frame
                appState.selectedWindowName = match.owningApplication?.applicationName ?? match.title
                repositionAreaOverlay()
            }
        }
    }
    
    private func refreshCachedWindows() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let systemApps: Set<String> = [
                    "ClipFocus", "Dock", "Window Server", "Control Center", "ControlCenter",
                    "Notification Center", "NotificationCenter", "SystemUIServer", "Spotlight",
                    "Wallpaper", "WindowManager", "loginwindow"
                ]
                let filtered = content.windows.filter { w in
                    guard let app = w.owningApplication?.applicationName, !systemApps.contains(app) else { return false }
                    return w.frame.width > 200 && w.frame.height > 150 && w.windowLayer == 0
                }
                await MainActor.run {
                    self.cachedUserWindows = filtered
                    let winInfos = filtered.map { w in
                        RecordedWindowInfo(
                            windowID: w.windowID,
                            appName: w.owningApplication?.applicationName ?? "App",
                            title: w.title ?? "",
                            frame: w.frame
                        )
                    }
                    self.appState?.availableWindows = winInfos
                    if self.appState?.selectedWindowID == nil, let top = filtered.first {
                        self.appState?.selectedWindowID = top.windowID
                        self.appState?.selectedWindowFrame = top.frame
                        self.appState?.selectedWindowName = top.owningApplication?.applicationName ?? top.title
                    }
                }
            } catch {
                NSLog("Failed to cache shareable content windows: %@", error.localizedDescription)
            }
        }
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == launcherWindow {
            if appState?.currentView == .launcher {
                NSApplication.shared.terminate(nil)
            }
            return false
        } else if sender == permissionsWindow {
            appState?.showPermissionsWindow = false
            return false
        } else if sender == editorWindow {
            if let app = appState {
                app.checkUnsavedChanges { [weak self] in
                    self?.appState?.cleanupEditorPlayback()
                    self?.appState?.currentView = .launcher
                    self?.editorWindow?.orderOut(nil)
                    self?.updateWindows()
                }
            }
            return false
        }
        return false
    }
    
    public func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow {
            if win == editorWindow {
                // If user closes editor, return to launcher
                appState?.cleanupEditorPlayback()
                appState?.currentView = .launcher
            } else if win == permissionsWindow {
                appState?.showPermissionsWindow = false
            }
        }
    }
}

/// Reactive wrapper for recording pill so duration ticks smoothly
struct RecordingPillWrapper: View {
    @Bindable var appState: AppState
    
    var body: some View {
        FloatingRecordingPill(appState: appState)
            .preferredColorScheme(.dark)
    }
}
