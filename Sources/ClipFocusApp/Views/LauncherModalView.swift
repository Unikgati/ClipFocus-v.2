import SwiftUI

public struct LauncherModalView: View {
    @Bindable var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Unified Window Top Row (Level with native traffic lights at Y = 16)
            ZStack(alignment: .center) {
                // Layer 1: True Center Brand "ClipFocus" (No icon as requested)
                Text("ClipFocus")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                
                // Layer 2: Clearance for native window controls (Close, Min)
                HStack(alignment: .center) {
                    Spacer()
                        .frame(width: 76)
                    Spacer()
                    
                    Button(action: {
                        appState.openProjectDialog()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text("Open Project...")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .cursorHand()
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 32)
            
            // Main Window Content: Left 3 recording mode cards, Right Device & Tool
            HStack(alignment: .top, spacing: 20) {
                // Left Column: Recording Modes
                VStack(alignment: .leading, spacing: 10) {
                    if let error = appState.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                                .font(.system(size: 13))
                            Text(error)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Spacer()
                            Button(action: { appState.errorMessage = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(white: 0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.9, green: 0.4, blue: 0.1).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                        )
                    }
                    
                    Text("Please select the recording mode")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.60))
                    
                    HStack(spacing: 12) {
                        // 1. Full Screen
                        Button(action: {
                            appState.selectMode(.fullScreen)
                        }) {
                            ModeCardView(
                                title: "Full Screen",
                                isSelected: appState.selectedMode == .fullScreen
                            ) {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color(red: 0.12, green: 0.35, blue: 0.85), Color(red: 0.10, green: 0.18, blue: 0.55)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: 55))
                                        path.addCurve(to: CGPoint(x: 120, y: 30), control1: CGPoint(x: 40, y: 15), control2: CGPoint(x: 80, y: 65))
                                        path.addLine(to: CGPoint(x: 120, y: 75))
                                        path.addLine(to: CGPoint(x: 0, y: 75))
                                        path.closeSubpath()
                                    }
                                    .fill(Color.blue.opacity(0.4))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // 2. Custom
                        Button(action: {
                            appState.selectMode(.custom)
                        }) {
                            ModeCardView(
                                title: "Custom",
                                isSelected: appState.selectedMode == .custom
                            ) {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color(red: 0.12, green: 0.35, blue: 0.85), Color(red: 0.10, green: 0.18, blue: 0.55)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.8, dash: [4]))
                                        .frame(width: 56, height: 38)
                                        .background(Color.cyan.opacity(0.12))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // 3. Window
                        Button(action: {
                            appState.selectMode(.window)
                        }) {
                            ModeCardView(
                                title: "Window",
                                isSelected: appState.selectedMode == .window
                            ) {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color(red: 0.12, green: 0.35, blue: 0.85), Color(red: 0.10, green: 0.18, blue: 0.55)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.22))
                                        .frame(width: 58, height: 40)
                                        .overlay(
                                            VStack(spacing: 0) {
                                                HStack(spacing: 3) {
                                                    Circle().fill(Color.white.opacity(0.6)).frame(width: 3.5, height: 3.5)
                                                    Circle().fill(Color.white.opacity(0.6)).frame(width: 3.5, height: 3.5)
                                                    Circle().fill(Color.white.opacity(0.6)).frame(width: 3.5, height: 3.5)
                                                    Spacer()
                                                }
                                                .padding(4)
                                                Spacer()
                                            }
                                        )
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.3), lineWidth: 1))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider().overlay(Color.white.opacity(0.04))
                
                // Right Column: Device & Tool (Clean layout with custom unified dropdowns)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Device & Tool")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.60))
                    
                    // 1. Microphone Row (Custom Dropdown)
                    if !appState.hasMicPermission {
                        Button(action: {
                            appState.requestMicrophonePermission()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "mic.slash")
                                    .font(.system(size: 13))
                                    .frame(width: 32, height: 32)
                                    .background(Color(red: 0.13, green: 0.15, blue: 0.20))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(Color(white: 0.50))
                                
                                HStack {
                                    Text("Enable microphone...")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(white: 0.55))
                                        .lineLimit(1)
                                    
                                    Spacer(minLength: 4)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Color(white: 0.40))
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 0.13, green: 0.15, blue: 0.20))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        CustomDeviceDropdown(
                            iconName: appState.selectedMic == "None" ? "mic.slash" : "mic",
                            options: appState.availableMics,
                            selection: $appState.selectedMic
                        )
                    }
                    
                    // 3. System Audio Row (Custom Dropdown)
                    CustomDeviceDropdown(
                        iconName: appState.selectedAudio == "None" ? "speaker.slash" : "speaker.wave.2",
                        options: appState.availableAudio,
                        selection: $appState.selectedAudio
                    )
                }
                .frame(width: 216)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
        .ignoresSafeArea()
        .alert("Screen Recording Permission Required", isPresented: $appState.showPermissionPrompt) {
            Button("Open System Settings") {
                appState.captureManager.openScreenRecordingSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("macOS requires explicit permission for ClipFocus to capture your screen, windows, and mouse interactions.\n\nPlease enable ClipFocus in System Settings > Privacy & Security > Screen Recording.")
        }
    }
}

/// Custom dark dropdown component matching the exact UI design tokens
struct CustomDeviceDropdown: View {
    let iconName: String
    let options: [String]
    @Binding var selection: String
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon Square (32x32)
            Image(systemName: iconName)
                .font(.system(size: 13))
                .frame(width: 32, height: 32)
                .background(Color(red: 0.13, green: 0.15, blue: 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selection == "None" ? Color(white: 0.45) : Color(white: 0.85))
            
            // Custom Dropdown Button Trigger
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        selection = option
                    }) {
                        if selection == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection)
                        .font(.system(size: 12))
                        .foregroundStyle(selection == "None" ? Color(white: 0.55) : Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer(minLength: 4)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(white: 0.50))
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(isHovered ? Color(red: 0.16, green: 0.18, blue: 0.24) : Color(red: 0.13, green: 0.15, blue: 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.04), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .onHover { isHovered = $0 }
        }
    }
}

struct ModeCardView<Content: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let preview: Content
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            preview
                .frame(width: 116, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(width: 128)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color(red: 0.14, green: 0.17, blue: 0.24)
                : (isHovered ? Color(red: 0.13, green: 0.15, blue: 0.21) : Color(red: 0.11, green: 0.13, blue: 0.18))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected
                        ? Color(red: 0.05, green: 0.75, blue: 0.95)
                        : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04)),
                    lineWidth: isSelected ? 1.8 : 1
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .cursorHand()
    }
}

extension View {
    func cursorHand() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
