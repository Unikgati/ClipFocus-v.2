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
                    
                    Divider().overlay(Color.white.opacity(0.06))
                    
                    // Left Properties Sidebar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if activeSidebarTab == "camera" {
                                cameraPropertiesSection
                            } else {
                                canvasPropertiesSection
                            }
                        }
                        .padding(16)
                    }
                    .frame(width: 250)
                    .background(Color(red: 0.10, green: 0.11, blue: 0.15))
                    
                    Divider().overlay(Color.white.opacity(0.06))
                    
                    // Center Stage & Bottom Resizable Timeline
                    VStack(spacing: 0) {
                        // Main Stage / Artboard (Fills all available height)
                        stageView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
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
                    case 51, 117: // Delete / Backspace -> Delete Selected Block or Segment
                        appState.deleteSelected()
                        return nil
                    default:
                        break
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
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
            
            // B. Visual Style Sliders
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
    
    // MARK: - Sidebar: Camera / Zoom Properties
    @ViewBuilder
    private var cameraPropertiesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            Text("Zoom & 3D Settings")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            
            if let selID = appState.selectedKeyframeID, appState.zoomKeyframes.contains(where: { $0.id == selID }) {
                // Zoom Effect: [ 2D Zoom ]  [ 3D Motion ]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Zoom Effect")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Button(action: {
                            appState.activeEffectType = .zoom2D
                        }) {
                            Text("2D Zoom")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(appState.activeEffectType == .zoom2D ? Color.blue : Color.white.opacity(0.08))
                                .foregroundStyle(appState.activeEffectType == .zoom2D ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            appState.activeEffectType = .motion3D
                        }) {
                            Text("3D Motion")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(appState.activeEffectType == .motion3D ? Color.blue : Color.white.opacity(0.08))
                                .foregroundStyle(appState.activeEffectType == .motion3D ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Zoom Level Slider (1.0x to 4.0x) with Reset button!
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Zoom Level")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Reset") {
                            appState.activeZoomScale = 1.0
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                        
                        Text(appState.activeZoomScale <= 1.05 ? "1X" : String(format: "%.1fX", appState.activeZoomScale))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { appState.activeZoomScale },
                            set: { appState.activeZoomScale = $0 }
                        ),
                        in: 1.0...4.0,
                        step: 0.1
                    )
                    .tint(.blue)
                }
                
                // Apply to all 3D Motions button
                Button(action: {
                    appState.applyToAll3DMotions()
                }) {
                    Text("Apply to all 3D Motions")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Divider().overlay(Color.white.opacity(0.08))
                
                // 3D Tilt Mode (FocuSee Advanced 3D System)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("3D Tilt")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        if appState.activeTiltPreset == .auto {
                            Text("Auto Dynamic")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.cyan)
                        } else if appState.activeTiltPreset == .custom {
                            Text("Manual Angles")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.blue)
                        } else {
                            Text("Flat")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 3-Mode Selector: Flat / Auto / Custom
                    HStack(spacing: 6) {
                        tiltModeButton(preset: .flat, title: "Flat", icon: "square")
                        tiltModeButton(preset: .auto, title: "Auto 3D", icon: "wand.and.stars")
                        tiltModeButton(preset: .custom, title: "Custom", icon: "slider.horizontal.3")
                    }
                    
                    if appState.activeTiltPreset == .auto {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.cyan)
                            Text("Card tilts dynamically following focus & zoom direction.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                
                // Custom 3D Rotation Sliders (visible when Custom mode is selected)
                if appState.activeTiltPreset == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("3D Rotation Angles")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        // Pitch (X-Axis)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Pitch (X-Axis)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset") {
                                    appState.activeCustomPitch = 0
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                                .buttonStyle(.plain)
                                
                                Text(String(format: "%.1f°", appState.activeCustomPitch))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            Slider(
                                value: Binding(
                                    get: { appState.activeCustomPitch },
                                    set: { appState.activeCustomPitch = $0 }
                                ),
                                in: -45...45
                            )
                            .tint(.blue)
                        }
                        
                        // Yaw (Y-Axis)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Yaw (Y-Axis)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset") {
                                    appState.activeCustomYaw = 0
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                                .buttonStyle(.plain)
                                
                                Text(String(format: "%.1f°", appState.activeCustomYaw))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            Slider(
                                value: Binding(
                                    get: { appState.activeCustomYaw },
                                    set: { appState.activeCustomYaw = $0 }
                                ),
                                in: -45...45
                            )
                            .tint(.blue)
                        }
                        
                        // Roll (Z-Axis)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Roll (Z-Axis)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset") {
                                    appState.activeCustomRoll = 0
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                                .buttonStyle(.plain)
                                
                                Text(String(format: "%.1f°", appState.activeCustomRoll))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            Slider(
                                value: Binding(
                                    get: { appState.activeCustomRoll },
                                    set: { appState.activeCustomRoll = $0 }
                                ),
                                in: -30...30
                            )
                            .tint(.blue)
                        }
                    }
                }
                
                // Position Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    // X-Axis
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("X-Axis")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Reset") {
                                appState.activePositionX = 0
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                            .buttonStyle(.plain)
                            
                            Text("\(Int(appState.activePositionX))")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Slider(
                            value: Binding(
                                get: { appState.activePositionX },
                                set: { appState.activePositionX = $0 }
                            ),
                            in: -100...100
                        )
                        .tint(.blue)
                    }
                    
                    // Y-Axis
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Y-Axis")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Reset") {
                                appState.activePositionY = 0
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                            .buttonStyle(.plain)
                            
                            Text("\(Int(appState.activePositionY))")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Slider(
                            value: Binding(
                                get: { appState.activePositionY },
                                set: { appState.activePositionY = $0 }
                            ),
                            in: -100...100
                        )
                        .tint(.blue)
                    }
                }
            } else {
                // Unselected / Empty state
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(appState.zoomKeyframes.isEmpty ? "No Zoom on Timeline" : "No Zoom Block Selected")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(appState.zoomKeyframes.isEmpty 
                        ? "Add a zoom block to the timeline to adjust 3D camera angles, scale, and position."
                        : "Click any zoom block on the timeline to adjust its zoom scale, 3D tilt, and position.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        appState.addZoomKeyframe(at: appState.currentTime)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Zoom Block")
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
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
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func tiltModeButton(preset: TiltPreset, title: String, icon: String) -> some View {
        let isSelected = appState.activeTiltPreset == preset
        Button(action: {
            appState.activeTiltPreset = preset
            appState.evaluateCurrentZoom()
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? (preset == .auto ? Color.cyan.opacity(0.3) : Color.blue.opacity(0.28)) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? (preset == .auto ? Color.cyan : Color.blue) : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Unified Full-Width Top Title Bar
    @ViewBuilder
    private var unifiedTitleBar: some View {
        ZStack {
            // Layer 1: True Center Brand "ClipFocus" (Level with native traffic lights at Y = 16)
            Text("ClipFocus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            
            // Layer 2: Left Native Traffic Light Space (76px) + Right Export Action
            HStack(alignment: .center) {
                Spacer().frame(width: 76)
                
                Spacer()
                
                Button(action: { appState.exportVideo() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.square.fill")
                        Text("Export Video")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4.5)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)
        }
        .frame(height: 32)
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
            }
            .buttonStyle(.plain)
            .help("Zoom & 3D Camera")
            
            // Dock Tab 3: Cursor
            Button(action: { activeSidebarTab = "cursor" }) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(activeSidebarTab == "cursor" ? .white : .secondary)
                    .frame(width: 38, height: 38)
                    .background(activeSidebarTab == "cursor" ? Color.white.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Cursor Settings")
            
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
                        let bgScale = max(1.0, zoomScale)
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
                        
                        // Video Player View with 3D Cinematic Perspective & After Effects Radial Motion Blur
                        let pad = CGFloat(appState.padding)
                        let availW = max(180, artboardSize.width - (pad * 2.0))
                        let availH = max(120, artboardSize.height - (pad * 2.0))
                        let vRatio = max(0.2, appState.videoAspectRatio)
                        
                        // Card dimensions strictly aspect-fit the recorded video ratio so video edges touch card boundaries exactly
                        let fitByWidth = (availW / availH) <= vRatio
                        let cardW: CGFloat = fitByWidth ? availW : (availH * vRatio)
                        let cardH: CGFloat = fitByWidth ? (availW / vRatio) : availH
                        
                        let is3D = appState.currentIs3D
                        let shadowRadius = CGFloat(appState.shadow) + (is3D ? 16.0 : 0.0)
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
                            cornerRadius: CGFloat(appState.roundness),
                            shadowRadius: shadowRadius,
                            is3DEnabled: is3D
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
                
                // Playback Speed & Volume
                HStack(spacing: 10) {
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
                    
                    Button {
                        appState.toggleAudioMute()
                    } label: {
                        Image(systemName: appState.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(appState.isAudioMuted ? Color.red : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Master Mute")
                    
                    Slider(value: $appState.audioVolume, in: 0...1) { _ in
                        appState.setVolume(appState.audioVolume)
                    }
                    .frame(width: 55)
                    .tint(.blue)
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
                    let trackWidth = max(100, geo.size.width - 24)
                    let totalDur = max(0.1, appState.totalDuration)
                    
                    ZStack(alignment: .topLeading) {
                        Color(red: 0.07, green: 0.08, blue: 0.11)
                        
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
                                        totalDur: totalDur
                                    )
                                    .padding(.horizontal, 10)
                                }
                            }
                            .coordinateSpace(name: "TimelineTrackContainer")
                            .frame(height: 32)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.clearSelection()
                                if let sec = hoverTimelineSec {
                                    appState.seek(to: sec, accurate: true)
                                }
                            }
                            
                            // 3. Track 2: Zoom Keyframes Track (Motion Blocks)
                            ZStack(alignment: .leading) {
                                // Clean Background track surface (tap on empty space to add zoom block immediately)
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
                                    .onTapGesture {
                                        let clickSec = hoverTimelineSec ?? appState.currentTime
                                        let isInside = appState.zoomKeyframes.contains { kf in
                                            clickSec >= kf.startTime && clickSec < (kf.startTime + kf.duration)
                                        }
                                        if !isInside {
                                            appState.addZoomKeyframe(at: clickSec)
                                            appState.seek(to: clickSec, accurate: true)
                                            activeSidebarTab = "camera"
                                        }
                                    }
                                    .gesture(
                                        DragGesture(minimumDistance: 6)
                                            .onChanged { value in
                                                appState.isScrubbing = true
                                                let ratio = max(0.0, min(1.0, (value.location.x - 10) / trackWidth))
                                                appState.seek(to: Double(ratio) * appState.totalDuration)
                                            }
                                            .onEnded { _ in
                                                appState.isScrubbing = false
                                            }
                                    )
                                
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
                            .frame(height: 30)
                            
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
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.clearSelection()
                                if let sec = hoverTimelineSec {
                                    appState.seek(to: sec, accurate: true)
                                }
                            }
                            
                            Spacer(minLength: 0)
                        }
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
                    }
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
            .frame(height: max(75, timelineHeight - 40))
        }
        .frame(height: timelineHeight)
    }
    
    // MARK: - Dynamic Timeline Ruler
    @ViewBuilder
    private func dynamicRuler(trackWidth: CGFloat) -> some View {
        let dur = max(1.0, appState.totalDuration)
        let step: Double = dur <= 10 ? 1.0 : (dur <= 30 ? 2.0 : (dur <= 60 ? 5.0 : 10.0))
        let tickCount = Int(dur / step)
        
        HStack(spacing: 0) {
            ForEach(0...tickCount, id: \.self) { i in
                let sec = Double(i) * step
                if sec <= dur {
                    Text(formatSeconds(sec))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if i < tickCount { Spacer() }
                }
            }
        }
        .padding(.horizontal, 10)
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
            }
            .padding(24)
            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
    
    // Helper time formats
    private func formatSeconds(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
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
        let isSelected = appState.selectedSegmentID == currentSeg.id && appState.selectedTrackType == .video
        
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
                                    appState.selectSegment(id: currentSeg.id, trackType: .video)
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
                    appState.selectSegment(id: currentSeg.id, trackType: .video)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
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
    
    var body: some View {
        let currentSeg = appState.audioSegments.first(where: { $0.id == seg.id }) ?? seg
        let startRatio = max(0.0, min(1.0, currentSeg.timelineStartTime / totalDur))
        let durationRatio = max(0.005, min(1.0, currentSeg.duration / totalDur))
        let xPos = CGFloat(startRatio) * trackWidth
        let blockW = max(20, CGFloat(durationRatio) * trackWidth)
        let isSelected = appState.selectedSegmentID == currentSeg.id && appState.selectedTrackType == .audio
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
            
            // Waveform Visualizer Bars mapped to clip's time range
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let samples = appState.audioWaveformSamples
                
                HStack(spacing: 2) {
                    if samples.isEmpty {
                        ForEach(0..<Int(max(5, w / 5)), id: \.self) { idx in
                            let phase = Double(idx) * 0.25
                            let s1 = sin(phase)
                            let s2 = sin(phase * 0.7)
                            let ampVal = 0.20 + 0.35 * s1 * s2
                            let amp = CGFloat(ampVal)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(red: 0.20, green: 0.85, blue: 0.65).opacity(isMuted ? 0.20 : 0.60))
                                .frame(width: 2, height: max(3, h * amp))
                        }
                    } else {
                        // Subsample corresponding to source range
                        let totalSamples = samples.count
                        let startFraction = currentSeg.sourceStartTime / max(0.1, appState.totalDuration)
                        let endFraction = (currentSeg.sourceStartTime + currentSeg.duration) / max(0.1, appState.totalDuration)
                        let startIdx = Int(max(0, min(Double(totalSamples - 1), startFraction * Double(totalSamples))))
                        let endIdx = Int(max(Double(startIdx + 1), min(Double(totalSamples), endFraction * Double(totalSamples))))
                        let slice = Array(samples[startIdx..<endIdx])
                        
                        ForEach(0..<slice.count, id: \.self) { idx in
                            let amp = CGFloat(slice[idx])
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(red: 0.20, green: 0.85, blue: 0.65).opacity(isMuted ? 0.20 : 0.80))
                                .frame(width: max(1.5, (w / CGFloat(max(1, slice.count))) - 2), height: max(3, h * amp))
                        }
                    }
                }
                .frame(width: w, height: h, alignment: .center)
            }
            .padding(.horizontal, 8)
            .allowsHitTesting(false)
            
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
                                    appState.selectSegment(id: currentSeg.id, trackType: .audio)
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
                    appState.selectSegment(id: currentSeg.id, trackType: .audio)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
                            appState.selectSegment(id: currentSeg.id, trackType: .audio)
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
                                }
                        )
                }
            }
        }
        .frame(width: blockW, height: 28)
        .shadow(color: isSelected ? Color.green.opacity(0.4) : Color.clear, radius: 4, y: 1)
        .offset(x: xPos)
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
        let isSelected = appState.selectedKeyframeID == currentKf.id
        
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
                                    if appState.selectedKeyframeID != currentKf.id {
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
                                    activeSidebarTab = "camera"
                                    appState.selectKeyframe(id: currentKf.id)
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
                    activeSidebarTab = "camera"
                    appState.selectKeyframe(id: currentKf.id)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
                            if appState.selectedKeyframeID != currentKf.id {
                                activeSidebarTab = "camera"
                                appState.selectKeyframe(id: currentKf.id)
                            }
                            if dragStart_StartSec == nil {
                                appState.recordUndoState()
                                dragStart_StartSec = currentKf.startTime
                            }
                            if let initStart = dragStart_StartSec {
                                let deltaX = value.location.x - value.startLocation.x
                                let deltaSec = Double(deltaX / trackWidth) * totalDur
                                let newStart = max(0, min(max(0, totalDur - currentKf.duration), initStart + deltaSec))
                                appState.updateKeyframeStartTime(id: currentKf.id, newStartTime: newStart)
                                appState.seek(to: newStart, accurate: false)
                            }
                        }
                        .onEnded { _ in
                            appState.isScrubbing = false
                            dragStart_StartSec = nil
                            appState.finalizeKeyframeEdits()
                            activeSidebarTab = "camera"
                            appState.selectKeyframe(id: currentKf.id)
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
                                    if appState.selectedKeyframeID != currentKf.id {
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
                                    activeSidebarTab = "camera"
                                    appState.selectKeyframe(id: currentKf.id)
                                }
                        )
                }
            }
        }
        .frame(width: blockW, height: 24)
        .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.clear, radius: 4, y: 1)
        .offset(x: xPos)
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
