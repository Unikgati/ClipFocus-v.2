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
                
                Menu("Auto-Stop Timer") {
                    Button(action: { appState.autoStopDuration = nil }) {
                        if appState.autoStopDuration == nil {
                            Label("Off (Manual Stop)", systemImage: "checkmark")
                        } else {
                            Text("Off (Manual Stop)")
                        }
                    }
                    Divider()
                    Button(action: { appState.autoStopDuration = 5 * 60 }) {
                        if appState.autoStopDuration == 5 * 60 { Label("5 Minutes", systemImage: "checkmark") } else { Text("5 Minutes") }
                    }
                    Button(action: { appState.autoStopDuration = 10 * 60 }) {
                        if appState.autoStopDuration == 10 * 60 { Label("10 Minutes", systemImage: "checkmark") } else { Text("10 Minutes") }
                    }
                    Button(action: { appState.autoStopDuration = 15 * 60 }) {
                        if appState.autoStopDuration == 15 * 60 { Label("15 Minutes", systemImage: "checkmark") } else { Text("15 Minutes") }
                    }
                    Button(action: { appState.autoStopDuration = 30 * 60 }) {
                        if appState.autoStopDuration == 30 * 60 { Label("30 Minutes", systemImage: "checkmark") } else { Text("30 Minutes") }
                    }
                    Button(action: { appState.autoStopDuration = 60 * 60 }) {
                        if appState.autoStopDuration == 60 * 60 { Label("60 Minutes", systemImage: "checkmark") } else { Text("60 Minutes") }
                    }
                    Divider()
                    Button("Custom Duration...") {
                        appState.showCustomTimerPrompt = true
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

            // 2b. Window Target Selector (When recording in Window Mode)
            if appState.selectedMode == .window {
                Menu {
                    if appState.availableWindows.isEmpty {
                        Text("No windows detected. Hover or click an open window.")
                    } else {
                        ForEach(appState.availableWindows) { win in
                            Button(action: {
                                appState.selectedWindowID = win.windowID
                                appState.selectedWindowFrame = win.frame
                                appState.selectedWindowName = win.appName + " - " + win.title
                                WindowManager.shared.updateWindows()
                            }) {
                                if appState.selectedWindowID == win.windowID {
                                    Label("\(win.appName): \(win.title.isEmpty ? "Main Window" : win.title)", systemImage: "checkmark")
                                } else {
                                    Text("\(win.appName): \(win.title.isEmpty ? "Main Window" : win.title)")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 12))
                        Text(appState.selectedWindowName ?? "Select Window")
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 125)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(Color.cyan)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.cyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            
            // 2c. Display Target Selector (When in Full Screen mode with multiple displays)
            if appState.selectedMode == .fullScreen && appState.availableDisplays.count > 1 {
                Menu {
                    ForEach(appState.availableDisplays) { disp in
                        Button(action: {
                            appState.selectedDisplayID = disp.id
                        }) {
                            if appState.selectedDisplayID == disp.id {
                                Label(disp.name, systemImage: "checkmark")
                            } else {
                                Text(disp.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "display")
                            .font(.system(size: 12))
                        Text(appState.selectedDisplayName)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 125)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }

            // 3. Microphone Menu / Permission
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
            
            // 5b. Record Auto-Stop Timer Menu (0% CPU overhead)
            Menu {
                Button(action: { appState.autoStopDuration = nil }) {
                    if appState.autoStopDuration == nil {
                        Label("Off (Manual Stop)", systemImage: "checkmark")
                    } else {
                        Text("Off (Manual Stop)")
                    }
                }
                
                Divider()
                
                let timerPresets: [(String, TimeInterval)] = [
                    ("5 Minutes", 5 * 60),
                    ("10 Minutes", 10 * 60),
                    ("15 Minutes", 15 * 60),
                    ("30 Minutes", 30 * 60),
                    ("45 Minutes", 45 * 60),
                    ("60 Minutes", 60 * 60)
                ]
                
                ForEach(timerPresets, id: \.1) { preset in
                    Button(action: { appState.autoStopDuration = preset.1 }) {
                        if appState.autoStopDuration == preset.1 {
                            Label(preset.0, systemImage: "checkmark")
                        } else {
                            Text(preset.0)
                        }
                    }
                }
                
                Divider()
                
                Button(action: {
                    appState.showCustomTimerPrompt = true
                }) {
                    Text("Custom Duration...")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 11.5, weight: appState.autoStopDuration != nil ? .bold : .medium))
                    Text(appState.autoStopTimerLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(appState.autoStopDuration != nil ? Color.blue : Color(white: 0.85))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(appState.autoStopDuration != nil ? Color.blue.opacity(0.12) : Color(red: 0.14, green: 0.16, blue: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(appState.autoStopDuration != nil ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Auto-Stop Recording Timer")

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
        .alert("Set Custom Recording Timer", isPresented: $appState.showCustomTimerPrompt) {
            TextField("Minutes (e.g. 20, 30, 45, 90)", text: $appState.customTimerMinutesText)
            Button("Set Timer") {
                let cleaned = appState.customTimerMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let mins = Double(cleaned), mins > 0 {
                    appState.autoStopDuration = mins * 60.0
                }
            }
            Button("Turn Off Timer", role: .destructive) {
                appState.autoStopDuration = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("ClipFocus will automatically stop recording and open the editor after the specified minutes.")
        }
    }
}
