import SwiftUI
import AppKit

public struct FloatingControlBarView: View {
    @Bindable var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // 1. Close Button (X) -> returns to main launcher
            Button(action: {
                appState.closeControlBar()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(white: 0.60))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 2. Settings Menu (Matching Focusee Settings Popup)
            Menu {
                Menu("Zoom Effect") {
                    Button(action: { appState.zoomDimension = .twoD }) {
                        if appState.zoomDimension == .twoD {
                            Label("2D Standard", systemImage: "checkmark")
                        } else {
                            Text("2D Standard")
                        }
                    }
                    Button(action: { appState.zoomDimension = .threeD }) {
                        if appState.zoomDimension == .threeD {
                            Label("3D Dynamic", systemImage: "checkmark")
                        } else {
                            Text("3D Dynamic")
                        }
                    }
                }
                
                Menu("Pre-Recording Countdown") {
                    Button(action: { appState.countdownSeconds = .none }) {
                        if appState.countdownSeconds == .none {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    Button(action: { appState.countdownSeconds = .threeSeconds }) {
                        if appState.countdownSeconds == .threeSeconds {
                            Label("3 Seconds", systemImage: "checkmark")
                        } else {
                            Text("3 Seconds")
                        }
                    }
                    Button(action: { appState.countdownSeconds = .fiveSeconds }) {
                        if appState.countdownSeconds == .fiveSeconds {
                            Label("5 Seconds", systemImage: "checkmark")
                        } else {
                            Text("5 Seconds")
                        }
                    }
                }
                
                Divider()
                
                Button(action: {
                    appState.hideDesktopIcons.toggle()
                }) {
                    if appState.hideDesktopIcons {
                        Label("Hide Desktop Icons", systemImage: "checkmark")
                    } else {
                        Text("Hide Desktop Icons")
                    }
                }
                
                Button(action: {
                    appState.autoZoomOnTyping.toggle()
                }) {
                    if appState.autoZoomOnTyping {
                        Label("Auto Zoom on Typing", systemImage: "checkmark")
                    } else {
                        Text("Auto Zoom on Typing")
                    }
                }
                
                Divider()
                
                Button("More Settings") {
                    appState.openMoreSettings()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 7)
                .frame(height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            
            // 3. Camera Permission / Selector button
            if !appState.hasCameraPermission {
                Button(action: {
                    appState.showPermissionsWindow = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 12))
                        Text("Enable the per...")
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(appState.availableCameras, id: \.self) { cam in
                        Button(action: { appState.selectedCamera = cam }) {
                            if appState.selectedCamera == cam {
                                Label(cam, systemImage: "checkmark")
                            } else {
                                Text(cam)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.selectedCamera == "None" ? "video.slash" : "video")
                            .font(.system(size: 12))
                        Text(appState.selectedCamera)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            
            // 4. Microphone Menu / Permission
            if !appState.hasMicPermission {
                Button(action: {
                    appState.requestMicrophonePermission()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 12))
                        Text("Enable mic per...")
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(appState.availableMics, id: \.self) { mic in
                        Button(action: { appState.selectedMic = mic }) {
                            if appState.selectedMic == mic {
                                Label(mic, systemImage: "checkmark")
                            } else {
                                Text(mic)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.selectedMic == "None" ? "mic.slash" : "mic")
                            .font(.system(size: 12))
                        Text(appState.selectedMic)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            
            // 5. System Audio Menu
            Menu {
                ForEach(appState.availableAudio, id: \.self) { audio in
                    Button(action: { appState.selectedAudio = audio }) {
                        if appState.selectedAudio == audio {
                            Label(audio, systemImage: "checkmark")
                        } else {
                            Text(audio)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: appState.selectedAudio == "None" ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 12))
                    Text(appState.selectedAudio)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color(red: 0.14, green: 0.16, blue: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            
            // 6. Circular Gradient REC Button (Matching Screenshot)
            Button(action: {
                appState.startCountdownAndRecord()
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.70, green: 0.50, blue: 1.0), Color(red: 0.55, green: 0.35, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(color: Color.purple.opacity(0.4), radius: 5, y: 1)
                    
                    if appState.isCountingDown {
                        Text("\(appState.countdownValue)")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                    } else {
                        Text("REC")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.09, green: 0.10, blue: 0.14))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
        .alert("Screen Recording Permission Required", isPresented: $appState.showPermissionPrompt) {
            Button("Open System Settings") {
                appState.captureManager.openScreenRecordingSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("macOS requires explicit permission for ClipFocus to capture your screen, windows, and mouse interactions.\n\nPlease enable ClipFocus in System Settings > Privacy & Security > Screen Recording.")
        }
        .alert("Camera Permission Required", isPresented: $appState.showCameraPermissionAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("ClipFocus requires camera access to display webcam feeds.\n\nPlease enable ClipFocus in System Settings > Privacy & Security > Camera.")
        }
    }
}
