import SwiftUI
import AVFoundation
import ClipFocusCore

public struct EditorStudioView: View {
    @Bindable var appState: AppState
    
    // Background gradient presets
    let wallpaperGradients: [LinearGradient] = [
        LinearGradient(colors: [Color.orange, Color.pink, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color.red, Color.orange, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color.blue, Color.purple, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color.indigo, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color.pink, Color.purple, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    ]
    
    let paletteColors: [Color] = [
        .blue, .indigo, .teal, .cyan, .yellow, .orange, .pink,
        Color(white: 0.15), Color(white: 0.25), Color(white: 0.35), Color(white: 0.50), Color(white: 0.65), Color(white: 0.80), Color(white: 0.95),
        Color.blue.opacity(0.4), Color.purple.opacity(0.4), Color.green.opacity(0.4), Color.teal.opacity(0.4), Color.yellow.opacity(0.4), Color.orange.opacity(0.4), Color.red.opacity(0.4)
    ]
    
    @State private var activeSidebarTab: String = "canvas"
    @State private var hoverTimelineSec: Double? = nil
    @State private var isHoveringTimeline: Bool = false
    @State private var isZoomTrackHovered: Bool = false
    @State private var timelineHeight: CGFloat = 180
    @State private var isHoveringSplitter: Bool = false
    @State private var dragStartTimelineHeight: CGFloat? = nil
    @State private var keyMonitor: Any? = nil
    @State private var gestureMonitor: Any? = nil
    @State private var isHoveringTimelineArea: Bool = false
    @State private var marqueeRect: CGRect? = nil
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 1. Full-Width Unified macOS Title Bar
                unifiedTitleBar
                
                Divider().overlay(Color.white.opacity(0.08))
                
                // 2. Main Studio Workspace
                HStack(spacing: 0) {
                    // Far Left Dock (Navigation Tabs)
                    dockView
                        .zIndex(101)
                    
                    Divider().overlay(Color.white.opacity(0.06))
                    
                    // Left Properties Sidebar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if activeSidebarTab == "camera" {
                                CameraPropertiesSidebarView(appState: appState)
                            } else {
                                canvasPropertiesSection
                            }
                        }
                        .padding(16)
                    }
                    .frame(width: 250)
                    .background(Color(red: 0.10, green: 0.11, blue: 0.15))
                    .contentShape(Rectangle())
                    .zIndex(100)
                    
                    Divider().overlay(Color.white.opacity(0.06))
                    
                    // Center Stage & Bottom Resizable Timeline
                    VStack(spacing: 0) {
                        // Main Stage / Artboard (Fills all available height)
                        stageView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .allowsHitTesting(false)
                        
                        // Resizable Timeline Splitter Handle
                        timelineSplitterView
                        
                        // Bottom Multi-Track Timeline & Transport
                        timelineView
                    }
                }
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            
            // Exporting Modal Overlay
            if appState.isExporting {
                exportingModal
            }
        }
        .ignoresSafeArea()
        .alert("Export Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "An error occurred.")
        }
        .alert("Export Successful", isPresented: Binding(
            get: { appState.exportSuccessMessage != nil },
            set: { if !$0 { appState.exportSuccessMessage = nil } }
        )) {
            Button("Show in Finder") {
                if let url = appState.lastExportedURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                appState.exportSuccessMessage = nil
            }
            Button("OK", role: .cancel) {
                appState.exportSuccessMessage = nil
            }
        } message: {
            Text(appState.exportSuccessMessage ?? "Your video has been exported successfully!")
        }
        .onAppear {
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // If user is actively typing in a text field, allow normal typing
                    if let responder = NSApp.keyWindow?.firstResponder, responder is NSText || responder is NSTextView {
                        return event
                    }
                    switch event.keyCode {
                    case 49: // Spacebar -> Play / Pause
                        appState.togglePlayback()
                        return nil
                    case 14: // E key with Cmd (Cmd+E) -> Export Video
                        if event.modifierFlags.contains(.command) {
                            appState.exportVideo()
                            return nil
                        }
                    case 1: // S key with Cmd (Cmd+S = Save, Cmd+Shift+S = Save As)
                        if event.modifierFlags.contains(.command) {
                            let isShift = event.modifierFlags.contains(.shift)
                            appState.saveProject(as: isShift)
                            return nil
                        }
                    case 31: // O key with Cmd (Cmd+O = Open Project/Video)
                        if event.modifierFlags.contains(.command) {
                            appState.openProjectDialog()
                            return nil
                        }
                    case 45: // N key with Cmd (Cmd+N = New Project)
                        if event.modifierFlags.contains(.command) {
                            appState.newProject()
                            return nil
                        }
                    case 11: // B key with Cmd (Cmd+B) -> Razor Cut / Split at Playhead
                        if event.modifierFlags.contains(.command) {
                            appState.splitAtCurrentTime()
                            return nil
                        }
                    case 6: // Z key with Cmd (Cmd+Z = Undo, Cmd+Shift+Z = Redo)
                        if event.modifierFlags.contains(.command) {
                            if event.modifierFlags.contains(.shift) {
                                appState.redo()
                            } else {
                                appState.undo()
                            }
                            return nil
                        }
                    case 16: // Y key with Cmd (Cmd+Y = Redo)
                        if event.modifierFlags.contains(.command) {
                            appState.redo()
                            return nil
                        }
                    case 37: // L -> Shuttle Forward (1x, 2x, 4x, 8x)
                        appState.shuttleForward()
                        return nil
                    case 40: // K -> Shuttle Stop / Pause
                        appState.shuttleStop()
                        return nil
                    case 38: // J -> Shuttle Reverse (-1x, -2x, -4x, -8x)
                        appState.shuttleReverse()
                        return nil
                    case 24: // = / + key with Cmd -> Zoom In Timeline
                        if event.modifierFlags.contains(.command) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.timelineZoomScale = min(5.0, appState.timelineZoomScale + 0.5)
                            }
                            return nil
                        }
                    case 27: // - key with Cmd -> Zoom Out Timeline
                        if event.modifierFlags.contains(.command) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.timelineZoomScale = max(1.0, appState.timelineZoomScale - 0.5)
                            }
                            return nil
                        }
                    case 29: // 0 key with Cmd -> Zoom to Fit
                        if event.modifierFlags.contains(.command) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.timelineZoomScale = 1.0
                            }
                            return nil
                        }
                    case 51, 117: // Delete / Backspace -> Delete Selected Block or Segment
                        appState.deleteSelected()
                        return nil
                    default:
                        break
                    }
                    return event
                }
            }
            if gestureMonitor == nil {
                gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { event in
                    guard isHoveringTimelineArea else { return event }
                    
                    switch event.type {
                    case .magnify:
                        // Native trackpad pinch-to-zoom (Premiere Pro style)
                        let delta = Double(event.magnification) * 4.0
                        withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.9)) {
                            appState.timelineZoomScale = max(1.0, min(8.0, appState.timelineZoomScale + delta))
                        }
                        return nil
                        
                    case .scrollWheel:
                        // Option + Scroll or Cmd + Scroll (Premiere Pro style)
                        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
                            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
                            if abs(dy) > 0.05 {
                                let delta = Double(dy) * 0.035
                                withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.9)) {
                                    appState.timelineZoomScale = max(1.0, min(8.0, appState.timelineZoomScale + delta))
                                }
                                return nil
                            }
                        }
                        return event
                        
                    default:
                        return event
                    }
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let gMonitor = gestureMonitor {
                NSEvent.removeMonitor(gMonitor)
                gestureMonitor = nil
            }
        }
    }
    
    // MARK: - Sidebar: Canvas & Styling
    @ViewBuilder
    private var canvasPropertiesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // A. Canvas Size & Aspect Ratio
            VStack(alignment: .leading, spacing: 8) {
                Text("Canvas Size")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(["Original", "16:9", "9:16"], id: \.self) { ratio in
                            aspectRatioButton(ratio)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(["1:1", "4:3"], id: \.self) { ratio in
                            aspectRatioButton(ratio)
                        }
                    }
                }
            }
            
            // B. Export Quality & Resolution
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Export Quality")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(exportQualityBadge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 5) {
                    ForEach(["1080p", "2K", "4K", "Auto"], id: \.self) { res in
                        exportResolutionButton(res)
                    }
                }
                
                Text(exportQualityDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // C. Visual Style Sliders
            VStack(alignment: .leading, spacing: 14) {
                Text("Frame Style")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Padding").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(appState.padding))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                    }
                    Slider(value: $appState.padding, in: 0...40).tint(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Roundness").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(appState.roundness))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                    }
                    Slider(value: $appState.roundness, in: 0...30).tint(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Shadow").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(appState.shadow))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                    }
                    Slider(value: $appState.shadow, in: 0...50).tint(.blue)
                }
            }
            
            // D. Background Gradients & Colors
            VStack(alignment: .leading, spacing: 10) {
                Text("Background")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                
                HStack(spacing: 5) {
                    ForEach(0..<wallpaperGradients.count, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(wallpaperGradients[idx])
                            .frame(height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(appState.activeBackgroundIndex == idx && appState.activeColorIndex == nil ? Color.white : Color.clear, lineWidth: 1.5)
                            )
                            .onTapGesture {
                                appState.activeBackgroundIndex = idx
                                appState.activeColorIndex = nil
                            }
                    }
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(0..<paletteColors.count, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(paletteColors[idx])
                            .frame(height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(appState.activeColorIndex == idx ? Color.white : Color.clear, lineWidth: 1.5)
                            )
                            .onTapGesture {
                                appState.activeColorIndex = idx
                            }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func aspectRatioButton(_ ratio: String) -> some View {
        let isSelected = appState.canvasRatio == ratio
        Button(action: {
            appState.canvasRatio = ratio
        }) {
            HStack(spacing: 4) {
                if ratio == "Original" {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 10))
                }
                Text(ratio)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue : Color.white.opacity(0.08))
            )
            .foregroundStyle(isSelected ? .white : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var exportQualityBadge: String {
        switch appState.exportResolution {
        case "4K": return "Ultra HD"
        case "2K": return "Quad HD"
        case "Auto": return "Native"
        default: return "Full HD"
        }
    }
    
    private var exportQualityDescription: String {
        switch appState.exportResolution {
        case "4K": return "3840×2160 • 60 FPS • Maximum crispness for 4K displays and keynote presentations."
        case "2K": return "2560×1440 • 60 FPS • Super sharp on Retina and QHD monitors."
        case "Auto": return "Matches native screen recording resolution with lossless pixel density."
        default: return "1920×1080 • 60 FPS • ~45 MB/min • Optimized for web, YouTube & fast sharing."
        }
    }
    
    @ViewBuilder
    private func exportResolutionButton(_ res: String) -> some View {
        let isSelected = appState.exportResolution == res
        Button(action: {
            appState.recordUndoState()
            appState.exportResolution = res
            appState.isDirty = true
        }) {
            Text(res)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.blue : Color.white.opacity(0.08))
                )
                .foregroundStyle(isSelected ? .white : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Unified Full-Width Top Title Bar
    @ViewBuilder
    private var unifiedTitleBar: some View {
        ZStack {
            // Layer 1: True Center Brand & Project Title (Level with native traffic lights at Y = 16)
            HStack(spacing: 7) {
                Text("ClipFocus")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.30))
                
                HStack(spacing: 5) {
                    Text(appState.projectTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                    
                    if appState.isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .help("Unsaved changes")
                    }
                }
            }
            
            // Layer 2: Left Native Traffic Light Space (76px) + Right Actions (Save & Export)
            HStack(alignment: .center) {
                Spacer().frame(width: 76)
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Save Button
                    Button(action: {
                        NSLog("[ClipFocus] User pressed Save button in titlebar")
                        appState.saveProject(as: false)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appState.isDirty ? .white : Color.white.opacity(0.65))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(appState.isDirty ? Color(red: 0.16, green: 0.20, blue: 0.30) : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(appState.isDirty ? Color.blue.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Save Project (⌘S)")
                    
                    // Export Button
                    Button(action: {
                        NSLog("[ClipFocus] User pressed Export button in titlebar")
                        appState.exportVideo()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.forward.square.fill")
                            Text("Export")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Export Video (⌘E)")
                }
            }
            .padding(.trailing, 16)
            
            // Layer 3: Floating Save Toast Overlay
            if appState.showSaveSuccessToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 12))
                    Text("Project Saved")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color(red: 0.11, green: 0.14, blue: 0.20).opacity(0.95))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 40)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }
    
    // MARK: - Far Left Dock (Navigation Tabs)
    @ViewBuilder
    private var dockView: some View {
        VStack(spacing: 14) {
            // Dock Tab 1: Canvas & Style
            Button(action: { activeSidebarTab = "canvas" }) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(activeSidebarTab == "canvas" ? .white : .secondary)
                    .frame(width: 38, height: 38)
                    .background(activeSidebarTab == "canvas" ? Color.white.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Canvas & Styling")
            
            // Dock Tab 2: 3D Camera / Zoom
            Button(action: { activeSidebarTab = "camera" }) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(activeSidebarTab == "camera" ? .white : .secondary)
                    .frame(width: 38, height: 38)
                    .background(activeSidebarTab == "camera" ? Color.white.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Zoom & 3D Camera")

            
            Spacer()
            
            // Back to launcher button at bottom
            Button(action: {
                appState.cleanupEditorPlayback()
                appState.currentView = .launcher
            }) {
                Image(systemName: "arrow.left.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to Launcher")
        }
        .padding(.top, 12)
        .frame(width: 56)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }
    
    // MARK: - Center Stage & Dynamic Artboard
    @ViewBuilder
    private var stageView: some View {
        GeometryReader { stageGeo in
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.10)
                
                // Artboard Frame dynamically sized to aspect ratio
                let artboardSize = calculateArtboardDimensions(in: stageGeo.size)
                
                let activeVid = appState.activeVideoSegment(at: appState.currentTime)
                
                ZStack {
                    if activeVid == nil && appState.avPlayer != nil {
                        // Empty cut / deleted video: Entire artboard frame is completely solid black
                        Color.black
                    } else if let player = appState.avPlayer, activeVid != nil {
                        // Dynamic Cinematic Background that zooms & pans along with the video zoom
                        let zoomScale = appState.currentZoomScale
                        let fx = appState.currentFocusPoint.x
                        let fy = appState.currentFocusPoint.y
                        
                        // Background camera zoom: scales up in tandem with the video zoom and tracks focus point
                        let bgScale = max(1.0, 1.0 + (zoomScale - 1.0) * 0.40)
                        let bgOffsetX = (0.5 - fx) * artboardSize.width * (bgScale - 1.0) * 0.40
                        let bgOffsetY = (0.5 - fy) * artboardSize.height * (bgScale - 1.0) * 0.40
                        
                        Group {
                            if let colorIdx = appState.activeColorIndex {
                                paletteColors[colorIdx]
                            } else {
                                wallpaperGradients[appState.activeBackgroundIndex]
                            }
                        }
                        .scaleEffect(bgScale)
                        .offset(x: bgOffsetX, y: bgOffsetY)
                        
                        // Video Player View with 3D Cinematic Perspective & Canonical Stage Reference
                        let canonicalSize = appState.canonicalArtboardDimensions()
                        let previewScale = artboardSize.width / canonicalSize.width
                        
                        let pad = CGFloat(appState.padding) * previewScale
                        let availW = max(50, artboardSize.width - (pad * 2.0))
                        let availH = max(50, artboardSize.height - (pad * 2.0))
                        let vRatio = max(0.2, appState.videoAspectRatio)
                        
                        // Card dimensions strictly aspect-fit the recorded video ratio so video edges touch card boundaries exactly
                        let fitByWidth = (availW / availH) <= vRatio
                        let cardW: CGFloat = fitByWidth ? availW : (availH * vRatio)
                        let cardH: CGFloat = fitByWidth ? (availW / vRatio) : availH
                        
                        let is3D = appState.currentIs3D
                        let shadowRadius = (CGFloat(appState.shadow) + (is3D ? 16.0 : 0.0)) * previewScale
                        let cornerRadius = CGFloat(appState.roundness) * previewScale
                        let pitchAngle = appState.currentPitch
                        let yawAngle = appState.currentYaw
                        let rollAngle = appState.currentRoll
                        
                        NativeVideoPlayerView(
                            player: player,
                            scale: zoomScale,
                            focusPoint: appState.currentFocusPoint,
                            positionOffsetX: appState.currentPositionX,
                            positionOffsetY: appState.currentPositionY,
                            pitch: pitchAngle,
                            yaw: yawAngle,
                            roll: rollAngle,
                            cornerRadius: cornerRadius,
                            shadowRadius: shadowRadius,
                            is3DEnabled: is3D,
                            previewScale: previewScale
                        )
                        .frame(width: cardW, height: cardH)
                    } else {
                        // Demo fallback placeholder
                        Color(red: 0.08, green: 0.09, blue: 0.12)
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 32))
                            Text("No Video Loaded")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Record a screen clip to start editing")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: artboardSize.width, height: artboardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .clipped()
                .allowsHitTesting(false)
                .shadow(color: Color.black.opacity(0.45), radius: 18)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.canvasRatio)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.videoAspectRatio)
            }
        }
    }
    
    // MARK: - Resizable Splitter between Stage & Timeline
    @ViewBuilder
    private var timelineSplitterView: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.15)
            
            Divider().overlay(Color.white.opacity(0.08))
            
            // Center grip indicator pill
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isHoveringSplitter ? Color.blue : Color.white.opacity(0.25))
                .frame(width: 38, height: 3)
        }
        .frame(height: 7)
        .background(CustomCursorView(cursor: .resizeUpDown))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringSplitter = hovering
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if dragStartTimelineHeight == nil {
                        dragStartTimelineHeight = timelineHeight
                    }
                    if let startH = dragStartTimelineHeight {
                        let newH = startH - value.translation.height
                        timelineHeight = max(115, min(480, newH))
                    }
                }
                .onEnded { _ in
                    dragStartTimelineHeight = nil
                }
        )
    }
    
    // Calculate stage dimensions according to active aspect ratio (Maximizes available space)
    private func calculateArtboardDimensions(in available: CGSize) -> CGSize {
        let maxW = max(120, available.width - 24)
        let maxH = max(100, available.height - 24)
        
        switch appState.canvasRatio {
        case "16:9":
            let w = min(maxW, maxH * (16.0 / 9.0))
            return CGSize(width: w, height: w * (9.0 / 16.0))
        case "9:16":
            let h = min(maxH, maxW * (16.0 / 9.0))
            return CGSize(width: h * (9.0 / 16.0), height: h)
        case "1:1":
            let side = min(maxW, maxH)
            return CGSize(width: side, height: side)
        case "4:3":
            let w = min(maxW, maxH * (4.0 / 3.0))
            return CGSize(width: w, height: w * (3.0 / 4.0))
        default: // Original
            let ratio = appState.videoAspectRatio > 0 ? appState.videoAspectRatio : (16.0 / 10.0)
            let w = min(maxW, maxH * ratio)
            return CGSize(width: w, height: w / ratio)
        }
    }
    
    // MARK: - Multi-Track Interactive Timeline
    @ViewBuilder
    private var timelineView: some View {
        VStack(spacing: 0) {
            // 1. Professional Transport & Editing Toolbar
            HStack(spacing: 14) {
                // Edit Tools (Clean Icons Only - Zero Background Box Clutter)
                HStack(spacing: 12) {
                    // Undo (⌘Z)
                    Button(action: {
                        appState.undo()
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(appState.canUndo ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.canUndo)
                    .help("Undo (⌘Z)")
                    
                    // Redo (⇧⌘Z or ⌘Y)
                    Button(action: {
                        appState.redo()
                    }) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(appState.canRedo ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.canRedo)
                    .help("Redo (⇧⌘Z)")
                    
                    // Split / Razor Cut
                    Button(action: {
                        appState.splitAtCurrentTime()
                    }) {
                        Image(systemName: "scissors")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Split clip at playhead (⌘B)")
                    
                    // Delete Selected Item
                    let hasSelection = appState.selectedSegmentID != nil || appState.selectedKeyframeID != nil
                    Button(action: {
                        appState.deleteSelected()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(hasSelection ? Color.red.opacity(0.9) : Color.white.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasSelection)
                    .help("Delete selected block or clip (⌫)")
                    
                    // Add Zoom Keyframe
                    Button(action: {
                        appState.addZoomKeyframe(at: appState.currentTime)
                        activeSidebarTab = "camera"
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.cyan)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add zoom block at playhead")
                    
                    // Snapping Magnet
                    Button(action: {
                        appState.isSnappingEnabled.toggle()
                    }) {
                        Image(systemName: "magnet.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(appState.isSnappingEnabled ? Color.yellow : Color.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Magnet Snapping")
                }
                
                Spacer()
                
                // Playback Transport Controls (Jump to Start, Step Back, Play/Pause, Step Forward, Jump to End)
                HStack(spacing: 12) {
                    // Jump to Start (|◀)
                    Button(action: {
                        appState.jumpToStart()
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Go to Beginning (Home)")
                    
                    // Step Back 1s (◀)
                    Button(action: {
                        appState.stepBackward(seconds: 1.0)
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Step Back 1s (←)")
                    
                    // Play / Pause (▶ / ⏸)
                    Button(action: {
                        appState.togglePlayback()
                    }) {
                        Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Play / Pause (Space)")
                    
                    // Step Forward 1s (▶)
                    Button(action: {
                        appState.stepForward(seconds: 1.0)
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Step Forward 1s (→)")
                    
                    // Jump to End (▶|)
                    Button(action: {
                        appState.jumpToEnd()
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Go to End (End)")
                    
                    Text("\(formatTimeWithMillis(appState.currentTime)) / \(formatTimeWithMillis(appState.totalDuration))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                
                Spacer()
                
                // Playback Speed & Timeline Zoom (Professional NLE Editor Controls)
                HStack(spacing: 12) {
                    Menu {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { spd in
                            Button("\(String(format: "%.1f", spd))x") {
                                appState.setPlaybackSpeed(spd)
                            }
                        }
                    } label: {
                        Text("\(String(format: "%.1f", appState.playbackSpeed))x")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 48)
                    
                    Divider()
                        .frame(height: 16)
                        .overlay(Color.white.opacity(0.12))
                    
                    // Professional Timeline Zoom In/Out Controls
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.timelineZoomScale = max(1.0, appState.timelineZoomScale - 0.5)
                            }
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(appState.timelineZoomScale <= 1.01 ? Color.white.opacity(0.25) : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.timelineZoomScale <= 1.01)
                        .help("Zoom Out Timeline (⌘-)")
                        
                        Slider(value: $appState.timelineZoomScale, in: 1.0...8.0)
                            .frame(width: 80)
                            .tint(.blue)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.timelineZoomScale = min(8.0, appState.timelineZoomScale + 0.5)
                            }
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(appState.timelineZoomScale >= 7.99 ? Color.white.opacity(0.25) : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.timelineZoomScale >= 7.99)
                        .help("Zoom In Timeline (⌘+)")
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.timelineZoomScale = 1.0
                            }
                        } label: {
                            Text("\(Int(round(appState.timelineZoomScale * 100)))%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reset Timeline Zoom to 100% Fit (⌘0)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Color(red: 0.10, green: 0.11, blue: 0.15))
            
            Divider().overlay(Color.white.opacity(0.06))
            
            // 2. Timeline Workspace: Left Track Headers + Right Track Canvas
            HStack(spacing: 0) {
                // Left Track Header Controls Column (Width ~105px)
                VStack(alignment: .leading, spacing: 6) {
                    // Header Ruler Spacer
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("TRACKS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 16)
                    .padding(.horizontal, 8)
                    
                    // Track 1 Header (Video Track V1)
                    HStack(spacing: 5) {
                        Text("V1")
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        
                        Text("Video")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        
                        Spacer()
                        
                        Button {
                            appState.isVideoTrackHidden.toggle()
                        } label: {
                            Image(systemName: appState.isVideoTrackHidden ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(appState.isVideoTrackHidden ? Color.secondary : Color.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Video Track Visibility")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    
                    // Track 2 Header (3D Zoom Track Z1)
                    HStack(spacing: 5) {
                        Text("Z1")
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        
                        Text("Zoom")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        
                        Spacer()
                        
                        Button {
                            appState.addZoomKeyframe(at: appState.currentTime)
                            activeSidebarTab = "camera"
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.cyan)
                        }
                        .buttonStyle(.plain)
                        .help("Add Zoom Block at Playhead")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    
                    // Track 3 Header (Audio Track A1 with Mute Button)
                    HStack(spacing: 5) {
                        Text("A1")
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.15, green: 0.70, blue: 0.50))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        
                        Text("Audio")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        
                        Spacer()
                        
                        Button {
                            appState.toggleAudioMute()
                        } label: {
                            Image(systemName: appState.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(appState.isAudioMuted ? Color.red : Color(red: 0.20, green: 0.85, blue: 0.65))
                        }
                        .buttonStyle(.plain)
                        .help(appState.isAudioMuted ? "Unmute Audio Track" : "Mute Audio Track")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    
                    Spacer(minLength: 0)
                }
                .frame(width: 105)
                .padding(.leading, 8)
                .padding(.top, 4)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                
                Divider().overlay(Color.white.opacity(0.06))
                
                // Right Tracks Canvas
                GeometryReader { geo in
                    let baseTrackWidth = max(100, geo.size.width - 24)
                    let trackWidth = baseTrackWidth * CGFloat(appState.timelineZoomScale)
                    let totalDur = max(0.1, appState.totalDuration)
                    let contentWidth = max(geo.size.width, trackWidth + 24)
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            Color(red: 0.07, green: 0.08, blue: 0.11)
                                .frame(width: contentWidth, height: geo.size.height)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .local)
                                        .onChanged { value in
                                            let start = value.startLocation
                                            let cur = value.location
                                            let box = CGRect(
                                                x: min(start.x, cur.x),
                                                y: min(start.y, cur.y),
                                                width: max(1, abs(cur.x - start.x)),
                                                height: max(1, abs(cur.y - start.y))
                                            )
                                            self.marqueeRect = box
                                            
                                            let isShift = NSEvent.modifierFlags.contains(.shift)
                                            let isCmd = NSEvent.modifierFlags.contains(.command)
                                            
                                            let startX = box.minX - 10
                                            let endX = box.maxX - 10
                                            let startSec = max(0, Double(startX / trackWidth) * totalDur)
                                            let endSec = min(totalDur, Double(endX / trackWidth) * totalDur)
                                            
                                            var hitKeyframeIDs: Set<UUID> = []
                                            var hitVideoIDs: Set<UUID> = []
                                            var hitAudioIDs: Set<UUID> = []
                                            
                                            if box.maxY >= 56 && box.minY <= 106 {
                                                for kf in appState.zoomKeyframes {
                                                    let kfEnd = kf.startTime + kf.duration
                                                    if kf.startTime <= endSec && kfEnd >= startSec {
                                                        hitKeyframeIDs.insert(kf.id)
                                                    }
                                                }
                                            }
                                            
                                            if box.maxY >= 20 && box.minY <= 64 {
                                                for seg in appState.videoSegments {
                                                    if seg.timelineStartTime <= endSec && seg.timelineEndTime >= startSec {
                                                        hitVideoIDs.insert(seg.id)
                                                    }
                                                }
                                            }
                                            
                                            if box.maxY >= 98 && box.minY <= 145 {
                                                for seg in appState.audioSegments {
                                                    if seg.timelineStartTime <= endSec && seg.timelineEndTime >= startSec {
                                                        hitAudioIDs.insert(seg.id)
                                                    }
                                                }
                                            }
                                            
                                            if !hitKeyframeIDs.isEmpty {
                                                activeSidebarTab = "camera"
                                                appState.selectMultipleKeyframes(ids: hitKeyframeIDs, isAdd: isShift || isCmd)
                                            } else if !hitVideoIDs.isEmpty {
                                                activeSidebarTab = "canvas"
                                                appState.selectMultipleSegments(ids: hitVideoIDs, trackType: .video, isAdd: isShift || isCmd)
                                            } else if !hitAudioIDs.isEmpty {
                                                appState.selectMultipleSegments(ids: hitAudioIDs, trackType: .audio, isAdd: isShift || isCmd)
                                            } else if !(isShift || isCmd) {
                                                appState.clearSelection()
                                            }
                                        }
                                        .onEnded { _ in
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                self.marqueeRect = nil
                                            }
                                        }
                                )
                            
                            VStack(alignment: .leading, spacing: 6) {
                            // 1. Dynamic Ruler
                            dynamicRuler(trackWidth: trackWidth)
                            
                            // 2. Track 1: Video Track (Segmented Media Clips)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white.opacity(0.015))
                                    .frame(height: 32)
                                    .padding(.horizontal, 10)
                                
                                ForEach(appState.videoSegments) { seg in
                                    VideoClipTimelineItemView(
                                        appState: appState,
                                        seg: seg,
                                        trackWidth: trackWidth,
                                        totalDur: totalDur,
                                        activeSidebarTab: $activeSidebarTab
                                    )
                                    .padding(.horizontal, 10)
                                }
                            }
                            .coordinateSpace(name: "TimelineTrackContainer")
                            .frame(width: trackWidth + 20, height: 32, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let isShift = NSEvent.modifierFlags.contains(.shift)
                                let isCmd = NSEvent.modifierFlags.contains(.command)
                                if !(isShift || isCmd) {
                                    appState.clearSelection()
                                }
                                if let sec = hoverTimelineSec {
                                    appState.seek(to: sec, accurate: true)
                                }
                            }
                            
                            // 3. Track 2: Zoom Keyframes Track (Motion Blocks)
                            ZStack(alignment: .leading) {
                                // Clean Background track surface (double-click on empty space to add zoom block, single-click to seek/deselect)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isZoomTrackHovered ? Color.cyan.opacity(0.04) : Color.white.opacity(0.015))
                                    .frame(height: 30)
                                    .padding(.horizontal, 10)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            isZoomTrackHovered = hovering
                                        }
                                    }
                                    .onTapGesture(count: 2) {
                                        let clickSec = hoverTimelineSec ?? appState.currentTime
                                        if let kf = appState.zoomKeyframes.first(where: { clickSec >= $0.startTime && clickSec < ($0.startTime + $0.duration) }) {
                                            appState.selectKeyframe(id: kf.id)
                                            activeSidebarTab = "camera"
                                        } else {
                                            appState.addZoomKeyframe(at: clickSec)
                                            appState.seek(to: clickSec, accurate: true)
                                            activeSidebarTab = "camera"
                                        }
                                    }
                                    .onTapGesture(count: 1) {
                                        let isShift = NSEvent.modifierFlags.contains(.shift)
                                        let isCmd = NSEvent.modifierFlags.contains(.command)
                                        let clickSec = hoverTimelineSec ?? appState.currentTime
                                        if let kf = appState.zoomKeyframes.first(where: { clickSec >= $0.startTime && clickSec < ($0.startTime + $0.duration) }) {
                                            appState.selectKeyframe(id: kf.id, isAdd: isShift || isCmd, isRange: isShift, seekTime: clickSec)
                                            activeSidebarTab = "camera"
                                        } else {
                                            appState.seek(to: clickSec, accurate: true)
                                            if !(isShift || isCmd) {
                                                appState.clearSelection()
                                            }
                                        }
                                    }
                                
                                // Interactive Keyframe Blocks with direct Drag & Resize Trim handles
                                ForEach(appState.zoomKeyframes) { kf in
                                    KeyframeTimelineItemView(
                                        appState: appState,
                                        kf: kf,
                                        trackWidth: trackWidth,
                                        totalDur: totalDur,
                                        activeSidebarTab: $activeSidebarTab
                                    )
                                    .padding(.horizontal, 10)
                                    .zIndex(30)
                                }
                            }
                            .coordinateSpace(name: "TimelineTrackContainer")
                            .frame(width: trackWidth + 20, height: 30, alignment: .leading)
                            
                            // 4. Track 3: Audio Waveform Track (Segmented Audio Clips)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white.opacity(0.015))
                                    .frame(height: 28)
                                    .padding(.horizontal, 10)
                                
                                ForEach(appState.audioSegments) { seg in
                                    AudioClipTimelineItemView(
                                        appState: appState,
                                        seg: seg,
                                        trackWidth: trackWidth,
                                        totalDur: totalDur
                                    )
                                    .padding(.horizontal, 10)
                                }
                            }
                            .coordinateSpace(name: "TimelineTrackContainer")
                            .frame(width: trackWidth + 20, height: 28, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let isShift = NSEvent.modifierFlags.contains(.shift)
                                let isCmd = NSEvent.modifierFlags.contains(.command)
                                if !(isShift || isCmd) {
                                    appState.clearSelection()
                                }
                                if let sec = hoverTimelineSec {
                                    appState.seek(to: sec, accurate: true)
                                }
                            }
                            
                            Spacer(minLength: 0)
                        }
                        .frame(width: trackWidth + 20, alignment: .leading)
                        .padding(.top, 4)
                        
                        // Hover Gray Skimmer Line (Clean Minimalist Pin spanning full track height)
                        if let hoverSec = hoverTimelineSec, !appState.isScrubbing {
                            let hoverRatio = max(0.0, min(1.0, hoverSec / totalDur))
                            let hoverX = CGFloat(hoverRatio) * trackWidth + 10
                            
                            Rectangle()
                                .fill(Color(white: 0.70).opacity(0.75))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                                .overlay(
                                    TrianglePin()
                                        .fill(Color(white: 0.75))
                                        .frame(width: 12, height: 9)
                                        .offset(y: -4),
                                    alignment: .top
                                )
                                .offset(x: hoverX)
                                .allowsHitTesting(false)
                        }
                        
                        // Main Playhead (Orange/Yellow Master Current Time Anchor spanning full track height)
                        let playheadRatio = max(0.0, min(1.0, appState.currentTime / totalDur))
                        let playheadX = CGFloat(playheadRatio) * trackWidth + 10
                        
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .overlay(
                                TrianglePin()
                                    .fill(Color.orange)
                                    .frame(width: 12, height: 9)
                                    .offset(y: -4),
                                alignment: .top
                            )
                            .offset(x: playheadX)
                            .allowsHitTesting(false)
                        
                        // Interactive Marquee Selection Box Overlay (Rubberband Box)
                        if let box = marqueeRect {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(red: 0.18, green: 0.55, blue: 0.95).opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color(red: 0.35, green: 0.75, blue: 1.0).opacity(0.85), lineWidth: 1)
                                )
                                .frame(width: box.width, height: box.height)
                                .position(x: box.midX, y: box.midY)
                                .allowsHitTesting(false)
                                .zIndex(90)
                        }
                        }
                        .frame(width: contentWidth, height: geo.size.height, alignment: .topLeading)
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case .active(let pt):
                                let ratio = max(0.0, min(1.0, (pt.x - 10) / trackWidth))
                                let sec = Double(ratio) * totalDur
                                hoverTimelineSec = sec
                                isHoveringTimeline = true
                                appState.previewHover(at: sec)
                            case .ended:
                                hoverTimelineSec = nil
                                isHoveringTimeline = false
                                appState.endHoverPreview()
                            }
                        }
                    }
                }
            }
            .frame(height: max(75, timelineHeight - 40))
        }
        .frame(height: timelineHeight)
        .onHover { hovering in
            isHoveringTimelineArea = hovering
        }
    }
    
    // MARK: - Dynamic Timeline Ruler (Clean Modern Ruler matching Gambar 2)
    @ViewBuilder
    private func dynamicRuler(trackWidth: CGFloat) -> some View {
        let dur = max(1.0, appState.totalDuration)
        
        // Adaptive major and minor tick intervals based on zoom scale
        let visibleDur = dur / max(1.0, appState.timelineZoomScale)
        let (majorStep, minorStep): (Double, Double) = {
            if visibleDur <= 4 {
                return (0.5, 0.1)
            } else if visibleDur <= 8 {
                return (1.0, 0.2)
            } else if visibleDur <= 16 {
                return (2.0, 0.5)
            } else if visibleDur <= 75 {
                return (5.0, 1.0)
            } else if visibleDur <= 150 {
                return (10.0, 2.0)
            } else if visibleDur <= 300 {
                return (15.0, 5.0)
            } else if visibleDur <= 600 {
                return (30.0, 10.0)
            } else {
                return (60.0, 15.0)
            }
        }()
        
        let minorCount = Int(dur / minorStep)
        let majorCount = Int(dur / majorStep)
        
        Canvas { context, size in
            // Horizontal baseline ruler line: starts exactly at x = 10, ends at x = 10 + trackWidth
            var basePath = Path()
            basePath.move(to: CGPoint(x: 10, y: 0.5))
            basePath.addLine(to: CGPoint(x: 10 + trackWidth, y: 0.5))
            context.stroke(basePath, with: .color(Color.white.opacity(0.14)), lineWidth: 1.0)
            
            // Minor tick marks
            var minorPath = Path()
            for i in 0...minorCount {
                let sec = Double(i) * minorStep
                let rem = sec.truncatingRemainder(dividingBy: majorStep)
                let isMajor = abs(rem) < 0.001 || abs(rem - majorStep) < 0.001
                if !isMajor && sec <= dur {
                    let x = CGFloat(sec / dur) * trackWidth + 10
                    minorPath.move(to: CGPoint(x: x, y: 0))
                    minorPath.addLine(to: CGPoint(x: x, y: 3.5))
                }
            }
            context.stroke(minorPath, with: .color(Color.white.opacity(0.20)), lineWidth: 1.0)
            
            // Major tick marks with labels
            for i in 0...majorCount {
                let sec = Double(i) * majorStep
                if sec <= dur {
                    let x = CGFloat(sec / dur) * trackWidth + 10
                    
                    var tickPath = Path()
                    tickPath.move(to: CGPoint(x: x, y: 0))
                    tickPath.addLine(to: CGPoint(x: x, y: 5.5))
                    context.stroke(tickPath, with: .color(Color.white.opacity(0.45)), lineWidth: 1.0)
                    
                    // Text label (e.g. 5s, 10s, 15s)
                    if sec > 0.05 && (x + 14) <= (trackWidth + 18) {
                        let text = Text(formatRulerTime(sec))
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.45))
                        context.draw(text, at: CGPoint(x: x, y: 8), anchor: .top)
                    }
                }
            }
        }
        .frame(width: trackWidth + 20, height: 18, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    appState.isScrubbing = true
                    let ratio = max(0.0, min(1.0, (value.location.x - 10) / trackWidth))
                    appState.seek(to: Double(ratio) * appState.totalDuration)
                }
                .onEnded { _ in
                    appState.isScrubbing = false
                }
        )
    }
    
    // MARK: - Exporting Progress Modal
    @ViewBuilder
    private var exportingModal: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Text("Exporting Video...")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                
                ProgressView(value: appState.exportProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(width: 240)
                
                Text("\(Int(appState.exportProgress * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Button(action: {
                    appState.cancelExport()
                }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
    
    private func formatRulerTime(_ seconds: Double) -> String {
        let totalSec = Int(round(seconds))
        if totalSec < 60 {
            return "\(totalSec)s"
        } else {
            let mins = totalSec / 60
            let remainder = totalSec % 60
            if remainder == 0 {
                return "\(mins)m"
            } else {
                return "\(mins)m \(remainder)s"
            }
        }
    }
    
    private func formatTimeWithMillis(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, millis)
    }
}

struct TrianglePin: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Native macOS Custom Cursor View using standard AppKit Cursor Rects
struct CustomCursorView: NSViewRepresentable {
    let cursor: NSCursor
    
    func makeNSView(context: Context) -> CustomCursorNSView {
        let v = CustomCursorNSView()
        v.cursor = cursor
        return v
    }
    
    func updateNSView(_ nsView: CustomCursorNSView, context: Context) {
        nsView.cursor = cursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

final class CustomCursorNSView: NSView {
    var cursor: NSCursor = .arrow
    private var trackingArea: NSTrackingArea?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Crucial: Return nil so AppKit mouse tracking never intercepts SwiftUI gestures
        return nil
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }
    
    override func mouseEntered(with event: NSEvent) {
        cursor.push()
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }
}

/// Interactive Segmented Video Clip View with drag-drop and left/right trim handles
struct VideoClipTimelineItemView: View {
    @Bindable var appState: AppState
    let seg: MediaClipSegment
    let trackWidth: CGFloat
    let totalDur: Double
    @Binding var activeSidebarTab: String
    
    @State private var dragStart_StartSec: Double? = nil
    @State private var dragStart_DurSec: Double? = nil
    @State private var isHoveringLeftHandle = false
    @State private var isHoveringRightHandle = false
    @State private var isHoveringBody = false
    
    var body: some View {
        let currentSeg = appState.videoSegments.first(where: { $0.id == seg.id }) ?? seg
        let startRatio = max(0.0, min(1.0, currentSeg.timelineStartTime / totalDur))
        let durationRatio = max(0.005, min(1.0, currentSeg.duration / totalDur))
        let xPos = CGFloat(startRatio) * trackWidth
        let blockW = max(20, CGFloat(durationRatio) * trackWidth)
        let isSelected = appState.selectedSegmentIDs.contains(currentSeg.id) && appState.selectedTrackType == .video
        
        ZStack(alignment: .leading) {
            // Clip background
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [Color(red: 0.58, green: 0.22, blue: 0.95), Color(red: 0.44, green: 0.14, blue: 0.82)]
                            : [Color(red: 0.42, green: 0.14, blue: 0.74), Color(red: 0.30, green: 0.08, blue: 0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.white : Color.purple.opacity(0.4), lineWidth: isSelected ? 1.5 : 0.8)
                )
            
            // 3-Zone Interactive Layout
            HStack(spacing: 0) {
                // Left Trim Handle
                if blockW >= 24 {
                    Rectangle()
                        .fill(Color.white.opacity(isHoveringLeftHandle ? 0.25 : 0.001))
                        .frame(width: 8, height: 32)
                        .background(CustomCursorView(cursor: .resizeLeftRight))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringLeftHandle = hovering
                            if hovering { NSCursor.resizeLeftRight.set() }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                                .onChanged { value in
                                    appState.isScrubbing = true
                                    activeSidebarTab = "canvas"
                                    if !appState.selectedSegmentIDs.contains(currentSeg.id) {
                                        appState.selectSegment(id: currentSeg.id, trackType: .video)
                                    }
                                    if dragStart_StartSec == nil {
                                        appState.recordUndoState()
                                        dragStart_StartSec = currentSeg.timelineStartTime
                                        dragStart_DurSec = currentSeg.duration
                                    }
                                    if let initStart = dragStart_StartSec {
                                        let deltaX = value.location.x - value.startLocation.x
                                        let deltaSec = Double(deltaX / trackWidth) * totalDur
                                        let newStart = initStart + deltaSec
                                        appState.trimSegmentStart(id: currentSeg.id, trackType: .video, newTimelineStart: newStart)
                                        appState.seek(to: currentSeg.timelineStartTime, accurate: false)
                                    }
                                }
                                .onEnded { _ in
                                    appState.isScrubbing = false
                                    dragStart_StartSec = nil
                                    dragStart_DurSec = nil
                                    appState.rebuildPlaybackComposition(maintainPlayhead: true)
                                }
                        )
                }
                
                // Center Move Body
                HStack(spacing: 5) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.85))
                    
                    if blockW >= 60 {
                        Text(currentSeg.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if blockW >= 40 {
                        Text(formatSecShort(currentSeg.duration))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CustomCursorView(cursor: .openHand))
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringBody = hovering
                    if hovering { NSCursor.openHand.set() }
                }
                .onTapGesture {
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    let isCmd = NSEvent.modifierFlags.contains(.command)
                    activeSidebarTab = "canvas"
                    appState.selectSegment(id: currentSeg.id, trackType: .video, isAdd: isShift || isCmd, isRange: isShift)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
                            activeSidebarTab = "canvas"
                            appState.selectSegment(id: currentSeg.id, trackType: .video)
                            if dragStart_StartSec == nil {
                                appState.recordUndoState()
                                dragStart_StartSec = currentSeg.timelineStartTime
                            }
                            if let initStart = dragStart_StartSec {
                                let deltaX = value.location.x - value.startLocation.x
                                let deltaSec = Double(deltaX / trackWidth) * totalDur
                                let newStart = initStart + deltaSec
                                appState.moveSegment(id: currentSeg.id, trackType: .video, newTimelineStart: newStart)
                                appState.seek(to: currentSeg.timelineStartTime, accurate: false)
                            }
                        }
                        .onEnded { _ in
                            appState.isScrubbing = false
                            dragStart_StartSec = nil
                            appState.rebuildPlaybackComposition(maintainPlayhead: true)
                        }
                )
                
                // Right Trim Handle
                if blockW >= 24 {
                    Rectangle()
                        .fill(Color.white.opacity(isHoveringRightHandle ? 0.25 : 0.001))
                        .frame(width: 8, height: 32)
                        .background(CustomCursorView(cursor: .resizeLeftRight))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringRightHandle = hovering
                            if hovering { NSCursor.resizeLeftRight.set() }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                                .onChanged { value in
                                    appState.isScrubbing = true
                                    appState.selectSegment(id: currentSeg.id, trackType: .video)
                                    if dragStart_DurSec == nil {
                                        appState.recordUndoState()
                                        dragStart_DurSec = currentSeg.duration
                                    }
                                    if let initDur = dragStart_DurSec {
                                        let deltaX = value.location.x - value.startLocation.x
                                        let deltaSec = Double(deltaX / trackWidth) * totalDur
                                        let newDur = initDur + deltaSec
                                        appState.trimSegmentEnd(id: currentSeg.id, trackType: .video, newDuration: newDur)
                                        appState.seek(to: currentSeg.timelineEndTime, accurate: false)
                                    }
                                }
                                .onEnded { _ in
                                    appState.isScrubbing = false
                                    dragStart_DurSec = nil
                                    appState.rebuildPlaybackComposition(maintainPlayhead: true)
                                }
                        )
                }
            }
        }
        .frame(width: blockW, height: 32)
        .shadow(color: isSelected ? Color.purple.opacity(0.5) : Color.clear, radius: 4, y: 1)
        .offset(x: xPos)
    }
}

/// Interactive Segmented Audio Clip View with embedded waveform visualization, drag-drop and trimming
struct AudioClipTimelineItemView: View {
    @Bindable var appState: AppState
    let seg: MediaClipSegment
    let trackWidth: CGFloat
    let totalDur: Double
    
    @State private var dragStart_StartSec: Double? = nil
    @State private var dragStart_DurSec: Double? = nil
    @State private var isHoveringLeftHandle = false
    @State private var isHoveringRightHandle = false
    @State private var isHoveringBody = false
    @State private var cachedBars: [Float] = []
    
    var body: some View {
        let currentSeg = appState.audioSegments.first(where: { $0.id == seg.id }) ?? seg
        let startRatio = max(0.0, min(1.0, currentSeg.timelineStartTime / totalDur))
        let durationRatio = max(0.005, min(1.0, currentSeg.duration / totalDur))
        let xPos = CGFloat(startRatio) * trackWidth
        let blockW = max(20, CGFloat(durationRatio) * trackWidth)
        let isSelected = appState.selectedSegmentIDs.contains(currentSeg.id) && appState.selectedTrackType == .audio
        let isMuted = currentSeg.isMuted || appState.isAudioMuted
        
        ZStack(alignment: .leading) {
            // Clip background
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [Color(red: 0.08, green: 0.32, blue: 0.24), Color(red: 0.05, green: 0.22, blue: 0.18)]
                            : [Color(red: 0.04, green: 0.20, blue: 0.16), Color(red: 0.03, green: 0.14, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.white : Color(red: 0.20, green: 0.85, blue: 0.65).opacity(0.35), lineWidth: isSelected ? 1.5 : 0.8)
                )
            
            // Professional NLE Audio Waveform Visualizer (Hardware-Accelerated Cached Canvas)
            GeometryReader { geo in
                let bars = cachedBars
                
                Canvas { context, size in
                    let midY = size.height / 2.0
                    
                    // 1. Center baseline hairline for true silence across entire clip
                    var baselinePath = Path()
                    baselinePath.move(to: CGPoint(x: 0, y: midY))
                    baselinePath.addLine(to: CGPoint(x: size.width, y: midY))
                    context.stroke(
                        baselinePath,
                        with: .color(Color(red: 0.20, green: 0.85, blue: 0.65).opacity(isMuted ? 0.15 : 0.35)),
                        lineWidth: 1.0
                    )
                    
                    guard !bars.isEmpty else { return }
                    
                    let availableW = max(1.0, size.width)
                    let numBars = bars.count
                    let step = availableW / CGFloat(numBars)
                    let barWidth = max(1.0, step - 0.7)
                    let maxAmpHeight = (size.height / 2.0) - 2.0
                    
                    var wavePath = Path()
                    for (b, peakAmp) in bars.enumerated() {
                        let amp = CGFloat(peakAmp)
                        if amp > 0.015 {
                            let x = CGFloat(b) * step
                            let peakH = max(1.2, amp * maxAmpHeight)
                            let barRect = CGRect(
                                x: x,
                                y: midY - peakH,
                                width: barWidth,
                                height: peakH * 2.0
                            )
                            wavePath.addRoundedRect(in: barRect, cornerSize: CGSize(width: 0.8, height: 0.8))
                        }
                    }
                    
                    let waveColor = Color(red: 0.22, green: 0.88, blue: 0.68).opacity(isMuted ? 0.25 : 0.88)
                    context.fill(wavePath, with: .color(waveColor))
                }
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
                .task(id: "\(currentSeg.id)_\(currentSeg.sourceStartTime)_\(currentSeg.duration)_\(Int(geo.size.width))_\(appState.audioWaveformSamples.count)") {
                    computeWaveformBars(width: geo.size.width, currentSeg: currentSeg)
                }
            }
            
            // 3-Zone Interactive Layout
            HStack(spacing: 0) {
                // Left Trim Handle
                if blockW >= 24 {
                    Rectangle()
                        .fill(Color.white.opacity(isHoveringLeftHandle ? 0.25 : 0.001))
                        .frame(width: 8, height: 28)
                        .background(CustomCursorView(cursor: .resizeLeftRight))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringLeftHandle = hovering
                            if hovering { NSCursor.resizeLeftRight.set() }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                                .onChanged { value in
                                    appState.isScrubbing = true
                                    if !appState.selectedSegmentIDs.contains(currentSeg.id) {
                                        appState.selectSegment(id: currentSeg.id, trackType: .audio)
                                    }
                                    if dragStart_StartSec == nil {
                                        appState.recordUndoState()
                                        dragStart_StartSec = currentSeg.timelineStartTime
                                        dragStart_DurSec = currentSeg.duration
                                    }
                                    if let initStart = dragStart_StartSec {
                                        let deltaX = value.location.x - value.startLocation.x
                                        let deltaSec = Double(deltaX / trackWidth) * totalDur
                                        let newStart = initStart + deltaSec
                                        appState.trimSegmentStart(id: currentSeg.id, trackType: .audio, newTimelineStart: newStart)
                                        appState.seek(to: currentSeg.timelineStartTime, accurate: false)
                                    }
                                }
                                .onEnded { _ in
                                    appState.isScrubbing = false
                                    dragStart_StartSec = nil
                                    dragStart_DurSec = nil
                                    appState.rebuildPlaybackComposition(maintainPlayhead: true)
                                }
                        )
                }
                
                // Center Move Body
                HStack(spacing: 4) {
                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if blockW >= 35 {
                        Text(formatSecShort(currentSeg.duration))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CustomCursorView(cursor: .openHand))
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringBody = hovering
                    if hovering { NSCursor.openHand.set() }
                }
                .onTapGesture {
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    let isCmd = NSEvent.modifierFlags.contains(.command)
                    appState.selectSegment(id: currentSeg.id, trackType: .audio, isAdd: isShift || isCmd, isRange: isShift)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
                            if !appState.selectedSegmentIDs.contains(currentSeg.id) {
                                appState.selectSegment(id: currentSeg.id, trackType: .audio)
                            }
                            if dragStart_StartSec == nil {
                                appState.recordUndoState()
                                dragStart_StartSec = currentSeg.timelineStartTime
                            }
                            if let initStart = dragStart_StartSec {
                                let deltaX = value.location.x - value.startLocation.x
                                let deltaSec = Double(deltaX / trackWidth) * totalDur
                                let newStart = initStart + deltaSec
                                appState.moveSegment(id: currentSeg.id, trackType: .audio, newTimelineStart: newStart)
                                appState.seek(to: currentSeg.timelineStartTime, accurate: false)
                            }
                        }
                        .onEnded { _ in
                            appState.isScrubbing = false
                            dragStart_StartSec = nil
                            appState.rebuildPlaybackComposition(maintainPlayhead: true)
                        }
                )
                
                // Right Trim Handle
                if blockW >= 24 {
                    Rectangle()
                        .fill(Color.white.opacity(isHoveringRightHandle ? 0.25 : 0.001))
                        .frame(width: 8, height: 28)
                        .background(CustomCursorView(cursor: .resizeLeftRight))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringRightHandle = hovering
                            if hovering { NSCursor.resizeLeftRight.set() }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                                .onChanged { value in
                                    appState.isScrubbing = true
                                    appState.selectSegment(id: currentSeg.id, trackType: .audio)
                                    if dragStart_DurSec == nil {
                                        appState.recordUndoState()
                                        dragStart_DurSec = currentSeg.duration
                                    }
                                    if let initDur = dragStart_DurSec {
                                        let deltaX = value.location.x - value.startLocation.x
                                        let deltaSec = Double(deltaX / trackWidth) * totalDur
                                        let newDur = initDur + deltaSec
                                        appState.trimSegmentEnd(id: currentSeg.id, trackType: .audio, newDuration: newDur)
                                        appState.seek(to: currentSeg.timelineEndTime, accurate: false)
                                    }
                                }
                                .onEnded { _ in
                                    appState.isScrubbing = false
                                    dragStart_DurSec = nil
                                    appState.rebuildPlaybackComposition(maintainPlayhead: true)
                                }
                        )
                }
            }
        }
        .frame(width: blockW, height: 28)
        .shadow(color: isSelected ? Color.green.opacity(0.4) : Color.clear, radius: 4, y: 1)
        .offset(x: xPos)
    }
    
    private func computeWaveformBars(width: CGFloat, currentSeg: MediaClipSegment) {
        let samples = appState.audioWaveformSamples
        guard !samples.isEmpty else {
            cachedBars = []
            return
        }
        
        let totalSamples = samples.count
        let startFraction = max(0.0, currentSeg.sourceStartTime / max(0.1, appState.totalDuration))
        let endFraction = min(1.0, (currentSeg.sourceStartTime + currentSeg.duration) / max(0.1, appState.totalDuration))
        let startIdx = Int(max(0, min(Double(totalSamples - 1), startFraction * Double(totalSamples))))
        let endIdx = Int(max(Double(startIdx + 1), min(Double(totalSamples), endFraction * Double(totalSamples))))
        let count = endIdx - startIdx
        guard count > 0 else {
            cachedBars = []
            return
        }
        
        let barSpacing: CGFloat = 2.4
        let numBars = max(1, Int(max(1.0, width) / barSpacing))
        var bars = [Float](repeating: 0, count: numBars)
        
        for b in 0..<numBars {
            let subStart = startIdx + Int(Double(b) / Double(numBars) * Double(count))
            let subEnd = max(subStart + 1, startIdx + Int(Double(b + 1) / Double(numBars) * Double(count)))
            let clampedEnd = min(endIdx, subEnd)
            
            var peakAmp: Float = 0.0
            for s in subStart..<clampedEnd {
                let v = samples[s]
                if v > peakAmp {
                    peakAmp = v
                }
            }
            bars[b] = peakAmp
        }
        cachedBars = bars
    }
}

/// Interactive Timeline Keyframe Block with ultra-smooth Drag (move) and Trim Handles (resize start & duration)
struct KeyframeTimelineItemView: View {
    @Bindable var appState: AppState
    let kf: ZoomKeyframe
    let trackWidth: CGFloat
    let totalDur: Double
    @Binding var activeSidebarTab: String
    
    @State private var dragStart_StartSec: Double? = nil
    @State private var dragStart_DurSec: Double? = nil
    @State private var isHoveringLeftHandle = false
    @State private var isHoveringRightHandle = false
    @State private var isHoveringBody = false
    
    var body: some View {
        let currentKf = appState.zoomKeyframes.first(where: { $0.id == kf.id }) ?? kf
        let startRatio = max(0.0, min(1.0, currentKf.startTime / totalDur))
        let durationRatio = max(0.005, min(1.0, currentKf.duration / totalDur))
        let xPos = CGFloat(startRatio) * trackWidth
        let blockW = max(18, CGFloat(durationRatio) * trackWidth)
        let isSelected = appState.selectedKeyframeIDs.contains(currentKf.id)
        
        ZStack(alignment: .leading) {
            // Clean Modern Block Container (Zero intrusive white pills)
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [Color(red: 0.12, green: 0.68, blue: 0.95), Color(red: 0.08, green: 0.50, blue: 0.85)]
                            : [Color(red: 0.10, green: 0.48, blue: 0.70), Color(red: 0.06, green: 0.35, blue: 0.56)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.35), lineWidth: isSelected ? 1.5 : 0.8)
                )
            
            // Interactive 3-Zone Layout (Left Trim | Move Body | Right Trim) without visual clutter
            HStack(spacing: 0) {
                // Left Trim Zone (Invisible handle, changes cursor to resizeLeftRight)
                if blockW >= 24 {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 8, height: 24)
                        .background(CustomCursorView(cursor: .resizeLeftRight))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringLeftHandle = hovering
                            if hovering {
                                NSCursor.resizeLeftRight.set()
                            }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                                .onChanged { value in
                                    appState.isScrubbing = true
                                    if !appState.selectedKeyframeIDs.contains(currentKf.id) {
                                        activeSidebarTab = "camera"
                                        appState.selectKeyframe(id: currentKf.id)
                                    }
                                    if dragStart_StartSec == nil {
                                        appState.recordUndoState()
                                        dragStart_StartSec = currentKf.startTime
                                        dragStart_DurSec = currentKf.duration
                                    }
                                    if let initStart = dragStart_StartSec, let initDur = dragStart_DurSec {
                                        let deltaX = value.location.x - value.startLocation.x
                                        let deltaSec = Double(deltaX / trackWidth) * totalDur
                                        let oldEnd = initStart + initDur
                                        let newStart = max(0, min(oldEnd - 0.2, initStart + deltaSec))
                                        appState.trimKeyframeStart(id: currentKf.id, newStartTime: newStart)
                                        appState.seek(to: newStart, accurate: false)
                                    }
                                }
                                .onEnded { _ in
                                    appState.isScrubbing = false
                                    dragStart_StartSec = nil
                                    dragStart_DurSec = nil
                                    appState.finalizeKeyframeEdits()
                                }
                        )
                }
                
                // Center Move Body (Changes cursor to openHand, moves clip position)
                HStack(spacing: 3) {
                    Image(systemName: currentKf.effectType == .motion3D ? "cube.fill" : "viewfinder")
                        .font(.system(size: 9))
                    if blockW >= 46 {
                        Text(currentKf.effectType == .motion3D ? "3D \(String(format: "%.1f", currentKf.scale))x" : "\(String(format: "%.1f", currentKf.scale))x")
                            .font(.system(size: 9.5, weight: .bold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(CustomCursorView(cursor: .openHand))
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringBody = hovering
                    if hovering {
                        NSCursor.openHand.set()
                    }
                }
                .onTapGesture {
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    let isCmd = NSEvent.modifierFlags.contains(.command)
                    activeSidebarTab = "camera"
                    appState.selectKeyframe(id: currentKf.id, isAdd: isShift || isCmd, isRange: isShift)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            if !appState.selectedKeyframeIDs.contains(currentKf.id) {
                                activeSidebarTab = "camera"
                                appState.selectKeyframe(id: currentKf.id)
                            }
                            let deltaX = value.location.x - value.startLocation.x
                            appState.isScrubbing = true
                            if dragStart_StartSec == nil {
                                appState.recordUndoState()
                                dragStart_StartSec = currentKf.startTime
                            }
                            if let initStart = dragStart_StartSec {
                                let deltaSec = Double(deltaX / trackWidth) * totalDur
                                let newStart = max(0, min(max(0, totalDur - currentKf.duration), initStart + deltaSec))
                                appState.updateKeyframeStartTime(id: currentKf.id, newStartTime: newStart)
                                appState.seek(to: newStart, accurate: false)
                            }
                        }
                        .onEnded { value in
                            appState.isScrubbing = false
                            dragStart_StartSec = nil
                            appState.finalizeKeyframeEdits()
                        }
                )
                
                // Right Trim Zone (Invisible handle, changes cursor to resizeLeftRight)
                if blockW >= 24 {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 8, height: 24)
                        .background(CustomCursorView(cursor: .resizeLeftRight))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringRightHandle = hovering
                            if hovering {
                                NSCursor.resizeLeftRight.set()
                            }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                                .onChanged { value in
                                    appState.isScrubbing = true
                                    if !appState.selectedKeyframeIDs.contains(currentKf.id) {
                                        activeSidebarTab = "camera"
                                        appState.selectKeyframe(id: currentKf.id)
                                    }
                                    if dragStart_DurSec == nil {
                                        appState.recordUndoState()
                                        dragStart_DurSec = currentKf.duration
                                    }
                                    if let initDur = dragStart_DurSec {
                                        let deltaX = value.location.x - value.startLocation.x
                                        let deltaSec = Double(deltaX / trackWidth) * totalDur
                                        let newDur = max(0.2, min(totalDur - currentKf.startTime, initDur + deltaSec))
                                        appState.updateKeyframeDuration(id: currentKf.id, newDuration: newDur)
                                        let curEnd = currentKf.startTime + newDur
                                        appState.seek(to: curEnd, accurate: false)
                                    }
                                }
                                .onEnded { _ in
                                    appState.isScrubbing = false
                                    dragStart_DurSec = nil
                                    appState.finalizeKeyframeEdits()
                                }
                        )
                }
            }
        }
        .frame(width: blockW, height: 24)
        .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.clear, radius: 4, y: 1)
        .offset(x: xPos)
        .contextMenu {
            // Section 1: Zoom Effect Type
            Section("Zoom Effect") {
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeEffectType = .zoom2D
                } label: {
                    if currentKf.effectType == .zoom2D {
                        Label("2D Zoom (Flat)", systemImage: "checkmark")
                    } else {
                        Text("2D Zoom (Flat)")
                    }
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeEffectType = .motion3D
                } label: {
                    if currentKf.effectType == .motion3D {
                        Label("3D Motion Tilt", systemImage: "checkmark")
                    } else {
                        Text("3D Motion Tilt")
                    }
                }
            }
            
            // Section 2: Zoom Scale presets
            Section("Zoom Scale") {
                ForEach([1.5, 2.0, 2.5, 3.0, 4.0], id: \.self) { scale in
                    Button {
                        appState.selectKeyframe(id: currentKf.id)
                        appState.activeZoomScale = scale
                    } label: {
                        let isMatch = abs(currentKf.scale - scale) < 0.05
                        if isMatch {
                            Label(String(format: "%.1fx", scale), systemImage: "checkmark")
                        } else {
                            Text(String(format: "%.1fx", scale))
                        }
                    }
                }
            }
            
            // Section 3: 3D Tilt Modes
            Section("3D Tilt Preset") {
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .flat
                } label: {
                    if currentKf.tiltPreset == .flat {
                        Label("Flat (No Tilt)", systemImage: "checkmark")
                    } else {
                        Text("Flat (No Tilt)")
                    }
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .auto
                } label: {
                    if currentKf.tiltPreset == .auto {
                        Label("Auto 3D Dynamic", systemImage: "checkmark")
                    } else {
                        Text("Auto 3D Dynamic")
                    }
                }
            }
            
            // Section 4: Direct Custom 3D Tilt Angles (Direct adjustment right here!)
            Section("Custom 3D Tilt Angles") {
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = -10.0
                    appState.activeCustomYaw = 14.0
                    appState.activeCustomRoll = 0.0
                } label: {
                    let isMatch = currentKf.tiltPreset == .custom && abs(currentKf.customPitch - (-10.0)) < 1 && abs(currentKf.customYaw - 14.0) < 1
                    if isMatch {
                        Label("↗ Top-Right Tilt (-10°, 14°)", systemImage: "checkmark")
                    } else {
                        Text("↗ Top-Right Tilt (-10°, 14°)")
                    }
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = -10.0
                    appState.activeCustomYaw = -14.0
                    appState.activeCustomRoll = 0.0
                } label: {
                    let isMatch = currentKf.tiltPreset == .custom && abs(currentKf.customPitch - (-10.0)) < 1 && abs(currentKf.customYaw - (-14.0)) < 1
                    if isMatch {
                        Label("↖ Top-Left Tilt (-10°, -14°)", systemImage: "checkmark")
                    } else {
                        Text("↖ Top-Left Tilt (-10°, -14°)")
                    }
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = 10.0
                    appState.activeCustomYaw = 14.0
                    appState.activeCustomRoll = 0.0
                } label: {
                    let isMatch = currentKf.tiltPreset == .custom && abs(currentKf.customPitch - 10.0) < 1 && abs(currentKf.customYaw - 14.0) < 1
                    if isMatch {
                        Label("↘ Bottom-Right Tilt (10°, 14°)", systemImage: "checkmark")
                    } else {
                        Text("↘ Bottom-Right Tilt (10°, 14°)")
                    }
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = 10.0
                    appState.activeCustomYaw = -14.0
                    appState.activeCustomRoll = 0.0
                } label: {
                    let isMatch = currentKf.tiltPreset == .custom && abs(currentKf.customPitch - 10.0) < 1 && abs(currentKf.customYaw - (-14.0)) < 1
                    if isMatch {
                        Label("↙ Bottom-Left Tilt (10°, -14°)", systemImage: "checkmark")
                    } else {
                        Text("↙ Bottom-Left Tilt (10°, -14°)")
                    }
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = -16.0
                    appState.activeCustomYaw = 20.0
                    appState.activeCustomRoll = 0.0
                } label: {
                    let isMatch = currentKf.tiltPreset == .custom && abs(currentKf.customPitch - (-16.0)) < 1 && abs(currentKf.customYaw - 20.0) < 1
                    if isMatch {
                        Label("Dramatic Tilt (-16°, 20°)", systemImage: "checkmark")
                    } else {
                        Text("Dramatic Tilt (-16°, 20°)")
                    }
                }
            }
            
            // Section 5: Fine-Tune Tilt Steppers
            Section("Tilt Stepper (±5°)") {
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = max(-45.0, currentKf.customPitch - 5.0)
                } label: {
                    Label("Pitch Up (-5°)", systemImage: "arrow.up")
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = min(45.0, currentKf.customPitch + 5.0)
                } label: {
                    Label("Pitch Down (+5°)", systemImage: "arrow.down")
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomYaw = max(-45.0, currentKf.customYaw - 5.0)
                } label: {
                    Label("Yaw Left (-5°)", systemImage: "arrow.left")
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomYaw = min(45.0, currentKf.customYaw + 5.0)
                } label: {
                    Label("Yaw Right (+5°)", systemImage: "arrow.right")
                }
                
                Button {
                    appState.selectKeyframe(id: currentKf.id)
                    appState.activeTiltPreset = .custom
                    appState.activeCustomPitch = 0.0
                    appState.activeCustomYaw = 0.0
                    appState.activeCustomRoll = 0.0
                } label: {
                    Label("Reset Angles to 0°", systemImage: "arrow.counterclockwise")
                }
            }
            
            Divider()
            
            Button {
                activeSidebarTab = "camera"
                appState.selectKeyframe(id: currentKf.id)
            } label: {
                Label("Open in Sidebar Inspector", systemImage: "slider.horizontal.3")
            }
            
            Divider()
            
            Button(role: .destructive) {
                appState.deleteZoomKeyframe(id: currentKf.id)
            } label: {
                Label("Delete Zoom Block", systemImage: "trash")
            }
        }
    }
}

func formatSecShort(_ sec: Double) -> String {
    let m = Int(sec) / 60
    let s = Int(sec) % 60
    let tenths = Int((sec.truncatingRemainder(dividingBy: 1)) * 10)
    if m > 0 {
        return String(format: "%d:%02d", m, s)
    } else {
        return String(format: "%d.%ds", s, tenths)
    }
}
