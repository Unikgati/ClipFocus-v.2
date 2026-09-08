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
    
    @State private var activeSidebarTab: String = "camera"
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // 1. Far Left Dock (Navigation Tabs)
                VStack(spacing: 16) {
                    Spacer().frame(height: 38)
                    
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
                }
                .frame(width: 56)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                
                Divider().overlay(Color.white.opacity(0.06))
                
                // 2. Left Properties Sidebar
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
                
                // 3. Center Canvas & Bottom Timeline
                VStack(spacing: 0) {
                    // Canvas Header Bar
                    headerBar
                    
                    // Main Stage / Artboard
                    stageView
                    
                    Divider().overlay(Color.white.opacity(0.06))
                    
                    // Bottom Multi-Track Timeline & Transport
                    timelineView
                }
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            
            // Exporting Modal Overlay
            if appState.isExporting {
                exportingModal
            }
        }
    }
    
    // MARK: - Sidebar: Canvas & Styling
    @ViewBuilder
    private var canvasPropertiesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // A. Canvas Size & Aspect Ratio
            VStack(alignment: .leading, spacing: 10) {
                Text("Canvas Size")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                
                HStack(spacing: 4) {
                    ForEach(["Original", "16:9", "1:1", "4:3", "9:16"], id: \.self) { ratio in
                        Button(action: {
                            appState.canvasRatio = ratio
                        }) {
                            Text(ratio)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(appState.canvasRatio == ratio ? Color.blue : Color.white.opacity(0.08))
                                .foregroundStyle(appState.canvasRatio == ratio ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // B. 3D Cinematic Zoom Toggle
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("3D Cinematic Tilt")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $appState.is3DZoomEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .labelsHidden()
                }
                
                if appState.is3DZoomEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tilt Depth")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(appState.tiltIntensity * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Slider(value: $appState.tiltIntensity, in: 0.5...2.5)
                            .tint(.blue)
                    }
                }
            }
            
            // Zoom Scale Adjustment
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Zoom Level")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "%.1fx", appState.activeZoomScale))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                
                HStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { appState.activeZoomScale },
                            set: { appState.activeZoomScale = $0 }
                        ),
                        in: 1.2...4.0,
                        step: 0.1
                    )
                    .tint(.blue)
                    
                    Button("2.5x") {
                        appState.activeZoomScale = 2.5
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(abs(appState.activeZoomScale - 2.5) < 0.05 ? Color.blue : Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)
                }
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
    
    // MARK: - Sidebar: Camera / Zoom Properties
    @ViewBuilder
    private var cameraPropertiesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Zoom & 3D Settings")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            if appState.zoomKeyframes.isEmpty {
                // FocuSee style: When no zoom block exists, show clean add-zoom state
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No Zoom on Timeline")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Add a zoom block to the timeline to adjust 3D camera angles, scale, and duration.")
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
                .padding(.vertical, 28)
            } else {
                // Disable Zoom Toggle
                HStack {
                    Text("Disable Zoom")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $appState.disableZoom)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
                
                Divider().overlay(Color.white.opacity(0.08))
            
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
            
            // Duration control for selected keyframe
            if appState.selectedKeyframeID != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Duration")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.1fs", appState.activeDuration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    Slider(
                        value: Binding(
                            get: { appState.activeDuration },
                            set: { appState.activeDuration = $0 }
                        ),
                        in: 0.5...15.0,
                        step: 0.1
                    )
                    .tint(.cyan)
                }
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
                            in: -30...30
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
                            in: -30...30
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
                            in: -15...15
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
            
            Divider().overlay(Color.white.opacity(0.1))
            
            Text("Zoom Keyframes (\(appState.zoomKeyframes.count))")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            
            ForEach(appState.zoomKeyframes) { kf in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(format: "%.1f", kf.scale))x Zoom • \(kf.reason ?? "click")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("At \(formatSeconds(kf.startTime)) (Duration: \(String(format: "%.1f", kf.duration))s)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        appState.selectKeyframe(id: kf.id)
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        appState.deleteZoomKeyframe(id: kf.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(appState.selectedKeyframeID == kf.id ? 0.12 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectKeyframe(id: kf.id)
                }
            }
        }
        }
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
    
    // MARK: - Header Bar
    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Text(appState.recordedVideoURL?.lastPathComponent ?? "ClipFocus Project")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            
            if appState.recordedVideoURL != nil {
                Text("● Real Recording")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            Button(action: { appState.importLocalVideo() }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import Video")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            Button(action: { appState.exportVideo() }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.square.fill")
                    Text("Export Video")
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 42)
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
                
                ZStack {
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
                    if let player = appState.avPlayer {
                        let is3D = appState.currentIs3D
                        let pitchAngle = appState.currentPitch
                        let yawAngle = appState.currentYaw
                        let rollAngle = appState.currentRoll
                        
                        // FocuSee style padding: scales the space between video card and wallpaper background without cropping or adding black bars
                        let pad = CGFloat(appState.padding)
                        let availW = max(180, artboardSize.width - (pad * 2.0))
                        let availH = max(120, artboardSize.height - (pad * 2.0))
                        let vRatio = max(0.2, appState.videoAspectRatio)
                        
                        // Card dimensions strictly aspect-fit the recorded video ratio so video edges touch card boundaries exactly
                        let fitByWidth = (availW / availH) <= vRatio
                        let cardW: CGFloat = fitByWidth ? availW : (availH * vRatio)
                        let cardH: CGFloat = fitByWidth ? (availW / vRatio) : availH
                        
                        let shadowRadius = CGFloat(appState.shadow) + (is3D ? 16.0 : 0.0)
                        
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
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("No Video Loaded")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Record a screen clip or click 'Import Video' to start editing")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: artboardSize.width, height: artboardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 20)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: appState.canvasRatio)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: appState.videoAspectRatio)
            }
        }
    }
    
    // Calculate stage dimensions according to active aspect ratio
    private func calculateArtboardDimensions(in available: CGSize) -> CGSize {
        let maxW = min(700, available.width - 40)
        let maxH = min(400, available.height - 40)
        
        switch appState.canvasRatio {
        case "16:9":
            let w = min(maxW, maxH * (16.0 / 9.0))
            return CGSize(width: w, height: w * (9.0 / 16.0))
        case "9:16":
            let h = maxH
            return CGSize(width: h * (9.0 / 16.0), height: h)
        case "1:1":
            let side = min(maxW, maxH, 360)
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
            // Transport & Toolbar
            HStack(spacing: 12) {
                // Edit Actions
                HStack(spacing: 6) {
                    // 1. Add Zoom Keyframe
                    Button(action: {
                        appState.addZoomKeyframe(at: appState.currentTime)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Zoom")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    // 2. Cut / Split tool (clean minimal scissors icon)
                    Button(action: {
                        appState.splitAtCurrentTime()
                    }) {
                        Image(systemName: "scissors")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Split keyframe at playhead position")
                    
                    // 3. Delete Selected Keyframe (clean icon)
                    if let selID = appState.selectedKeyframeID {
                        Button(action: {
                            appState.deleteZoomKeyframe(id: selID)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.85))
                                .frame(width: 26, height: 26)
                                .background(Color.red.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Delete selected keyframe")
                    }
                }
                
                Spacer()
                
                // Playback Transport Controls
                HStack(spacing: 14) {
                    Button(action: {
                        appState.seek(to: max(0, appState.currentTime - 1.0))
                    }) {
                        Image(systemName: "gobackward.1")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        appState.togglePlayback()
                    }) {
                        Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        appState.seek(to: min(appState.totalDuration, appState.currentTime + 1.0))
                    }) {
                        Image(systemName: "goforward.1")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(formatTimeWithMillis(appState.currentTime)) / \(formatTimeWithMillis(appState.totalDuration))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
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
                    
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: $appState.audioVolume, in: 0...1) { _ in
                        appState.setVolume(appState.audioVolume)
                    }
                    .frame(width: 60)
                    .tint(.blue)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color(red: 0.10, green: 0.11, blue: 0.15))
            
            Divider().overlay(Color.white.opacity(0.06))
            
            // Tracks Canvas
            GeometryReader { geo in
                let trackWidth = max(100, geo.size.width - 28)
                
                ZStack(alignment: .leading) {
                    Color(red: 0.07, green: 0.08, blue: 0.11)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // 1. Dynamic Ruler
                        dynamicRuler(trackWidth: trackWidth)
                        
                        // 2. Track 1: Video Track (FocuSee purple clip)
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("▶ \(appState.recordedVideoURL?.lastPathComponent ?? "Recorded Clip")")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatSeconds(appState.totalDuration))
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 34)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.48, green: 0.16, blue: 0.82),
                                        Color(red: 0.36, green: 0.10, blue: 0.68)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.4), lineWidth: 1))
                        }
                        .padding(.horizontal, 14)
                        
                        // 3. Track 2: Zoom Keyframes Track (FocuSee cyan 3D Motion)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.03))
                                .frame(height: 30)
                                .padding(.horizontal, 14)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            appState.isScrubbing = true
                                            let ratio = max(0.0, min(1.0, (value.location.x - 14) / trackWidth))
                                            appState.seek(to: Double(ratio) * appState.totalDuration)
                                        }
                                        .onEnded { _ in
                                            appState.isScrubbing = false
                                        }
                                )
                            
                            // Interactive Keyframe Blocks with direct Drag & Resize Trim handles
                            let totalDur = max(0.1, appState.totalDuration)
                            ForEach(appState.zoomKeyframes) { kf in
                                KeyframeTimelineItemView(
                                    appState: appState,
                                    kf: kf,
                                    trackWidth: trackWidth,
                                    totalDur: totalDur,
                                    activeSidebarTab: $activeSidebarTab
                                )
                            }
                        }
                        .coordinateSpace(name: "TimelineTrackContainer")
                        .frame(height: 30)
                    }
                    .padding(.vertical, 8)
                    
                    let playheadRatio = max(0.0, min(1.0, appState.currentTime / max(0.1, appState.totalDuration)))
                    let playheadX = CGFloat(playheadRatio) * trackWidth + 14
                    
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 2)
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
            }
            .frame(height: 125)
        }
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
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    appState.isScrubbing = true
                    let ratio = max(0.0, min(1.0, (value.location.x - 14) / trackWidth))
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
        let startRatio = max(0.0, min(1.0, kf.startTime / totalDur))
        let durationRatio = max(0.01, min(1.0, kf.duration / totalDur))
        let xPos = CGFloat(startRatio) * trackWidth + 14
        let blockW = max(36, CGFloat(durationRatio) * trackWidth)
        let isSelected = appState.selectedKeyframeID == kf.id
        
        ZStack(alignment: .leading) {
            // Background Container
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
            
            // 3-Section Non-Overlapping Interactive Grid: [Left Handle] | [Center Move Body] | [Right Handle]
            HStack(spacing: 0) {
                // Left Trim Handle (always active, changes cursor to resizeLeftRight)
                ZStack {
                    Rectangle()
                        .fill(isSelected ? (isHoveringLeftHandle ? Color.white.opacity(0.35) : Color.white.opacity(0.001)) : Color.clear)
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 3.5, height: 13)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                    }
                }
                .frame(width: 14, height: 24)
                .background(CustomCursorView(cursor: .resizeLeftRight))
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringLeftHandle = hovering
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
                            if appState.selectedKeyframeID != kf.id {
                                activeSidebarTab = "camera"
                                appState.selectKeyframe(id: kf.id)
                            }
                            if dragStart_StartSec == nil {
                                dragStart_StartSec = kf.startTime
                                dragStart_DurSec = kf.duration
                            }
                            if let initStart = dragStart_StartSec, let initDur = dragStart_DurSec {
                                let deltaX = value.location.x - value.startLocation.x
                                let deltaSec = Double(deltaX / trackWidth) * totalDur
                                let oldEnd = initStart + initDur
                                let newStart = max(0, min(oldEnd - 0.2, initStart + deltaSec))
                                appState.trimKeyframeStart(id: kf.id, newStartTime: newStart)
                                appState.seek(to: newStart, accurate: false)
                            }
                        }
                        .onEnded { _ in
                            appState.isScrubbing = false
                            dragStart_StartSec = nil
                            dragStart_DurSec = nil
                            appState.finalizeKeyframeEdits()
                            if let updated = appState.zoomKeyframes.first(where: { $0.id == kf.id }) {
                                appState.seek(to: updated.startTime, accurate: true)
                            }
                        }
                )
                
                // Center Move Body (Changes cursor to openHand, moves clip position)
                HStack(spacing: 3) {
                    Image(systemName: kf.effectType == .motion3D ? "cube.fill" : "viewfinder")
                        .font(.system(size: 9))
                    Text(kf.effectType == .motion3D ? "3D \(String(format: "%.1f", kf.scale))x" : "\(String(format: "%.1f", kf.scale))x")
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(CustomCursorView(cursor: .openHand))
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringBody = hovering
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
                            if appState.selectedKeyframeID != kf.id {
                                activeSidebarTab = "camera"
                                appState.selectKeyframe(id: kf.id)
                            }
                            if dragStart_StartSec == nil {
                                dragStart_StartSec = kf.startTime
                            }
                            if let initStart = dragStart_StartSec {
                                let deltaX = value.location.x - value.startLocation.x
                                let deltaSec = Double(deltaX / trackWidth) * totalDur
                                let newStart = max(0, min(max(0, totalDur - kf.duration), initStart + deltaSec))
                                appState.updateKeyframeStartTime(id: kf.id, newStartTime: newStart)
                                appState.seek(to: newStart, accurate: false)
                            }
                        }
                        .onEnded { _ in
                            appState.isScrubbing = false
                            dragStart_StartSec = nil
                            appState.finalizeKeyframeEdits()
                            if let updated = appState.zoomKeyframes.first(where: { $0.id == kf.id }) {
                                appState.seek(to: updated.startTime, accurate: true)
                            }
                        }
                )
                
                // Right Trim Handle (always active, changes cursor to resizeLeftRight)
                ZStack {
                    Rectangle()
                        .fill(isSelected ? (isHoveringRightHandle ? Color.white.opacity(0.35) : Color.white.opacity(0.001)) : Color.clear)
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 3.5, height: 13)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                    }
                }
                .frame(width: 14, height: 24)
                .background(CustomCursorView(cursor: .resizeLeftRight))
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringRightHandle = hovering
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("TimelineTrackContainer"))
                        .onChanged { value in
                            appState.isScrubbing = true
                            if appState.selectedKeyframeID != kf.id {
                                activeSidebarTab = "camera"
                                appState.selectKeyframe(id: kf.id)
                            }
                            if dragStart_DurSec == nil {
                                dragStart_DurSec = kf.duration
                            }
                            if let initDur = dragStart_DurSec {
                                let deltaX = value.location.x - value.startLocation.x
                                let deltaSec = Double(deltaX / trackWidth) * totalDur
                                let newDur = max(0.2, min(totalDur - kf.startTime, initDur + deltaSec))
                                appState.updateKeyframeDuration(id: kf.id, newDuration: newDur)
                                let curEnd = kf.startTime + newDur
                                appState.seek(to: curEnd, accurate: false)
                            }
                        }
                        .onEnded { _ in
                            appState.isScrubbing = false
                            dragStart_DurSec = nil
                            appState.finalizeKeyframeEdits()
                            if let updated = appState.zoomKeyframes.first(where: { $0.id == kf.id }) {
                                appState.seek(to: updated.startTime + updated.duration, accurate: true)
                            }
                        }
                )
            }
        }
        .frame(width: blockW, height: 24)
        .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.clear, radius: 4, y: 1)
        .position(x: xPos + (blockW / 2), y: 15)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    activeSidebarTab = "camera"
                    appState.selectKeyframe(id: kf.id)
                }
        )
    }
}
