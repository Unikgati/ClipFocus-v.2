import SwiftUI
import ClipFocusCore

/// Dedicated, completely rebuilt Inspector Sidebar for Zoom & 3D Camera settings.
/// Engineered for 100% reliable clickability, responsive slider adjustments,
/// and live cinematic preview synchronization.
public struct CameraPropertiesSidebarView: View {
    @Bindable var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    /// Resolves the currently active keyframe index safely (Strict selection: only active when explicitly selected)
    private var activeIndex: Int? {
        if let id = appState.selectedKeyframeID,
           let idx = appState.zoomKeyframes.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return nil
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let idx = activeIndex, idx < appState.zoomKeyframes.count {
                activeKeyframeContent(idx: idx)
            } else {
                emptyStateView
            }
        }
    }
    
    // MARK: - Empty State (When no zoom block is active or selected)
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 12)
            
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.cyan)
            
            VStack(spacing: 6) {
                Text("No Zoom Block Active")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Select a zoom block on the timeline or add a new one at the playhead to edit 2D zoom and 3D camera angles.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 8)
            
            Button(action: {
                appState.addZoomKeyframe(at: appState.currentTime)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Zoom")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.blue)
                .clipShape(Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            
            Spacer(minLength: 20)
        }
    }
    
    // MARK: - Active Keyframe Inspector Content
    @ViewBuilder
    private func activeKeyframeContent(idx: Int) -> some View {
        let kf = appState.zoomKeyframes[idx]
        
        // 1. Header Title
        Text("Zoom & 3D Settings")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
        
        // 2. Zoom Effect Mode: [ 2D Zoom ]  [ 3D Motion ]
        VStack(alignment: .leading, spacing: 6) {
            Text("Zoom Effect")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
            
            HStack(spacing: 8) {
                zoomModeButton(
                    title: "2D Zoom",
                    icon: "viewfinder",
                    isSelected: kf.effectType == .zoom2D
                ) {
                    appState.zoomKeyframes[idx].effectType = .zoom2D
                    appState.zoomKeyframes[idx].tiltPreset = .flat
                    appState.selectedEffectType = .zoom2D
                    appState.selectedTiltPreset = .flat
                    appState.evaluateCurrentZoom()
                }
                
                zoomModeButton(
                    title: "3D Motion",
                    icon: "cube.fill",
                    isSelected: kf.effectType == .motion3D
                ) {
                    appState.zoomKeyframes[idx].effectType = .motion3D
                    if appState.zoomKeyframes[idx].tiltPreset == .flat {
                        appState.zoomKeyframes[idx].tiltPreset = .auto
                    }
                    appState.selectedEffectType = .motion3D
                    appState.evaluateCurrentZoom()
                }
            }
        }
        
        // 3. Zoom Level (Scale)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Zoom Level")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                resetIconButton(action: {
                    appState.zoomKeyframes[idx].scale = 1.0
                    appState.evaluateCurrentZoom()
                }, help: "Reset scale to 1.0X")
                
                Text(kf.scale <= 1.05 ? "1.0X" : String(format: "%.1fX", kf.scale))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            
            // Quick 1-Click Presets: 1.3x, 1.5x, 2.0x, 2.5x, 3.0x
            HStack(spacing: 5) {
                ForEach([1.3, 1.5, 2.0, 2.5, 3.0], id: \.self) { preset in
                    let isMatched = abs(kf.scale - preset) < 0.08
                    Button(action: {
                        appState.zoomKeyframes[idx].scale = preset
                        appState.defaultZoomScale = preset
                        appState.evaluateCurrentZoom()
                    }) {
                        Text(String(format: "%.1fx", preset))
                            .font(.system(size: 10, weight: isMatched ? .bold : .medium))
                            .foregroundStyle(isMatched ? .white : Color.white.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background(isMatched ? Color.blue : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Clean continuous slider without tick marks or stepper buttons
            Slider(
                value: Binding(
                    get: { idx < appState.zoomKeyframes.count ? appState.zoomKeyframes[idx].scale : 1.0 },
                    set: { val in
                        guard idx < appState.zoomKeyframes.count else { return }
                        appState.zoomKeyframes[idx].scale = max(1.0, min(4.0, val))
                        appState.defaultZoomScale = val
                        appState.evaluateCurrentZoom()
                    }
                ),
                in: 1.0...4.0
            )
            .tint(.blue)
        }
        
        // 4. 3D Tilt Settings
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("3D Tilt Preset")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                if kf.tiltPreset == .auto {
                    Text("Auto Dynamic")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)
                } else if kf.tiltPreset == .custom {
                    Text("Manual Custom")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)
                } else {
                    Text("Flat")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            // 3-Mode Selector: Flat | Auto 3D | Custom
            HStack(spacing: 6) {
                tiltModeButton(
                    title: "Flat",
                    icon: "square",
                    isSelected: kf.tiltPreset == .flat
                ) {
                    appState.zoomKeyframes[idx].tiltPreset = .flat
                    appState.zoomKeyframes[idx].effectType = .zoom2D
                    appState.evaluateCurrentZoom()
                }
                
                tiltModeButton(
                    title: "Auto 3D",
                    icon: "cube.fill",
                    isSelected: kf.tiltPreset == .auto
                ) {
                    appState.zoomKeyframes[idx].tiltPreset = .auto
                    appState.zoomKeyframes[idx].effectType = .motion3D
                    appState.evaluateCurrentZoom()
                }
                
                tiltModeButton(
                    title: "Custom",
                    icon: "slider.horizontal.3",
                    isSelected: kf.tiltPreset == .custom
                ) {
                    appState.zoomKeyframes[idx].tiltPreset = .custom
                    appState.zoomKeyframes[idx].effectType = .motion3D
                    // If all angles are 0, seed with beautiful continuous perspective angles
                    if kf.customPitch == 0 && kf.customYaw == 0 {
                        appState.zoomKeyframes[idx].customPitch = -10.0
                        appState.zoomKeyframes[idx].customYaw = 14.0
                    }
                    appState.evaluateCurrentZoom()
                }
            }
            
            if kf.tiltPreset == .auto {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.cyan)
                    Text("Card tilts dynamically following focus & zoom position.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        
        // 5. Custom 3D Angle Sliders & Quick Directions (shown when tiltPreset == .custom)
        if kf.tiltPreset == .custom {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom 3D Tilt Angles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                
                // Quick Angle Direction Presets
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        directionPresetButton(
                            title: "↗ Top-Right",
                            pitch: -10.0,
                            yaw: 14.0,
                            idx: idx,
                            currentPitch: kf.customPitch,
                            currentYaw: kf.customYaw
                        )
                        directionPresetButton(
                            title: "↖ Top-Left",
                            pitch: -10.0,
                            yaw: -14.0,
                            idx: idx,
                            currentPitch: kf.customPitch,
                            currentYaw: kf.customYaw
                        )
                    }
                    HStack(spacing: 5) {
                        directionPresetButton(
                            title: "↘ Bottom-Right",
                            pitch: 10.0,
                            yaw: 14.0,
                            idx: idx,
                            currentPitch: kf.customPitch,
                            currentYaw: kf.customYaw
                        )
                        directionPresetButton(
                            title: "↙ Bottom-Left",
                            pitch: 10.0,
                            yaw: -14.0,
                            idx: idx,
                            currentPitch: kf.customPitch,
                            currentYaw: kf.customYaw
                        )
                    }
                }
                
                // Pitch (X-Axis Tilt) Slider
                angleSliderRow(
                    label: "Pitch (X-Axis)",
                    value: Binding(
                        get: { idx < appState.zoomKeyframes.count ? appState.zoomKeyframes[idx].customPitch : 0.0 },
                        set: {
                            guard idx < appState.zoomKeyframes.count else { return }
                            appState.zoomKeyframes[idx].customPitch = $0
                            appState.evaluateCurrentZoom()
                        }
                    ),
                    range: -45.0...45.0
                )
                
                // Yaw (Y-Axis Tilt) Slider
                angleSliderRow(
                    label: "Yaw (Y-Axis)",
                    value: Binding(
                        get: { idx < appState.zoomKeyframes.count ? appState.zoomKeyframes[idx].customYaw : 0.0 },
                        set: {
                            guard idx < appState.zoomKeyframes.count else { return }
                            appState.zoomKeyframes[idx].customYaw = $0
                            appState.evaluateCurrentZoom()
                        }
                    ),
                    range: -45.0...45.0
                )
                
                // Roll (Z-Axis Rotation) Slider
                angleSliderRow(
                    label: "Roll (Z-Axis)",
                    value: Binding(
                        get: { idx < appState.zoomKeyframes.count ? appState.zoomKeyframes[idx].customRoll : 0.0 },
                        set: {
                            guard idx < appState.zoomKeyframes.count else { return }
                            appState.zoomKeyframes[idx].customRoll = $0
                            appState.evaluateCurrentZoom()
                        }
                    ),
                    range: -30.0...30.0
                )
            }
            .padding(10)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        
        // 6. Camera Position Pan Offsets
        VStack(alignment: .leading, spacing: 8) {
            Text("Pan Offset")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
            
            // X Offset
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("X Offset").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    resetIconButton(action: {
                        appState.zoomKeyframes[idx].positionOffsetX = 0
                        appState.evaluateCurrentZoom()
                    }, help: "Reset X Offset to 0")
                    Text("\(Int(kf.positionOffsetX))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white)
                }
                Slider(
                    value: Binding(
                        get: { idx < appState.zoomKeyframes.count ? appState.zoomKeyframes[idx].positionOffsetX : 0 },
                        set: {
                            guard idx < appState.zoomKeyframes.count else { return }
                            appState.zoomKeyframes[idx].positionOffsetX = $0
                            appState.evaluateCurrentZoom()
                        }
                    ),
                    in: -100...100
                )
                .tint(.blue)
            }
            
            // Y Offset
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Y Offset").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    resetIconButton(action: {
                        appState.zoomKeyframes[idx].positionOffsetY = 0
                        appState.evaluateCurrentZoom()
                    }, help: "Reset Y Offset to 0")
                    Text("\(Int(kf.positionOffsetY))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white)
                }
                Slider(
                    value: Binding(
                        get: { idx < appState.zoomKeyframes.count ? appState.zoomKeyframes[idx].positionOffsetY : 0 },
                        set: {
                            guard idx < appState.zoomKeyframes.count else { return }
                            appState.zoomKeyframes[idx].positionOffsetY = $0
                            appState.evaluateCurrentZoom()
                        }
                    ),
                    in: -100...100
                )
                .tint(.blue)
            }
        }
        
        // 7. Bulk Action: Apply to All Zoom Blocks
        Button(action: {
            appState.applyToAll3DMotions()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.2.layers.3d.top.filled")
                    .font(.system(size: 11))
                Text("Apply to All Zoom Blocks")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy scale and 3D mode from this block to all other zoom blocks")
    }
    
    // MARK: - Reusable UI Subviews
    
    @ViewBuilder
    private func zoomModeButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .lineLimit(1)
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue.opacity(0.9) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func tiltModeButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
            }
            .lineLimit(1)
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.85) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.10), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func directionPresetButton(
        title: String,
        pitch: Double,
        yaw: Double,
        idx: Int,
        currentPitch: Double,
        currentYaw: Double
    ) -> some View {
        let isMatch = abs(currentPitch - pitch) < 1.0 && abs(currentYaw - yaw) < 1.0
        Button(action: {
            appState.zoomKeyframes[idx].customPitch = pitch
            appState.zoomKeyframes[idx].customYaw = yaw
            appState.zoomKeyframes[idx].customRoll = 0.0
            appState.evaluateCurrentZoom()
        }) {
            Text(title)
                .font(.system(size: 10, weight: isMatch ? .bold : .medium))
                .foregroundStyle(isMatch ? .white : Color.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(isMatch ? Color.blue : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func angleSliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                resetIconButton(action: {
                    value.wrappedValue = 0.0
                }, help: "Reset angle to 0°")
                
                Text(String(format: "%.1f°", value.wrappedValue))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            
            Slider(value: value, in: range)
                .tint(.blue)
        }
    }
    
    @ViewBuilder
    private func resetIconButton(action: @escaping () -> Void, help: String = "Reset") -> some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
