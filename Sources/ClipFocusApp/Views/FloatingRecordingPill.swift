import SwiftUI

/// Floating Recording Bar styled with precision matching the user's reference (FocuSee recording bar)
/// and uniform in height and aesthetics with FloatingControlBarView.
public struct FloatingRecordingPill: View {
    @Bindable var appState: AppState
    
    @State private var isTrashHovered: Bool = false
    @State private var isRestartHovered: Bool = false
    @State private var isPauseHovered: Bool = false
    @State private var isStopHovered: Bool = false
    @State private var showDiscardConfirm: Bool = false
    @State private var showRestartConfirm: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        Group {
            if appState.isFinalizingRecording {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Processing & Opening Editor...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
            } else if showDiscardConfirm {
                HStack(spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                    Text("Discard?")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDiscardConfirm = false
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    
                    Button("Discard") {
                        showDiscardConfirm = false
                        appState.discardRecording()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.90, green: 0.25, blue: 0.25))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
            } else if showRestartConfirm {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Restart?")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showRestartConfirm = false
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    
                    Button("Restart") {
                        showRestartConfirm = false
                        appState.restartRecording()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.46, green: 0.36, blue: 0.98))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
            } else if appState.captureManager.isLowDiskSpacePaused {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.15))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Low Disk: Paused")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white)
                        if let bytes = appState.captureManager.availableDiskSpaceBytes {
                            Text("Sisa \(bytes / (1024 * 1024)) MB")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                    }
                    
                    Spacer()
                    
                    // Resume button (Green)
                    Button(action: {
                        appState.togglePauseRecording()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("Resume")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Color(red: 0.12, green: 0.68, blue: 0.38))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Lanjutkan perekaman setelah membersihkan disk")
                    
                    // Stop & Save button (Purple)
                    Button(action: {
                        appState.triggerStopRecording()
                    }) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 7, height: 7)
                            Text("Save")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Color(red: 0.46, green: 0.36, blue: 0.98))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Simpan rekaman yang sudah ada")
                    
                    // Discard button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDiscardConfirm = true
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.65))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Batal & hapus rekaman")
                }
                .padding(.horizontal, 10)
            } else {
                HStack(spacing: 16) {
                    // 1. Trash Button (Discard current recording)
                    Button(action: {
                        if appState.captureManager.recordingDuration >= 3.0 {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showDiscardConfirm = true
                            }
                        } else {
                            appState.discardRecording()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isTrashHovered ? Color(red: 1.0, green: 0.35, blue: 0.35) : Color(white: 0.65))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isTrashHovered = $0 }
                    .help("Discard Recording")
                    
                    // 2. Restart Button (Restart from 00:00)
                    Button(action: {
                        if appState.captureManager.recordingDuration >= 3.0 {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showRestartConfirm = true
                            }
                        } else {
                            appState.restartRecording()
                        }
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isRestartHovered ? Color.white : Color(white: 0.65))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isRestartHovered = $0 }
                    .help("Restart Recording")
                    
                    // 3. Pause / Resume Button
                    Button(action: {
                        appState.togglePauseRecording()
                    }) {
                        Image(systemName: appState.isRecordingPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isPauseHovered ? Color.white : (appState.isRecordingPaused ? Color(red: 0.05, green: 0.80, blue: 1.0) : Color(white: 0.70)))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isPauseHovered = $0 }
                    .help(appState.isRecordingPaused ? "Resume Recording" : "Pause Recording")
                    
                    // 4. Stop Recording Button (Purple Glowing Circular Button with White Stop Square)
                    Button(action: {
                        appState.triggerStopRecording()
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.46, green: 0.36, blue: 0.98),
                                            Color(red: 0.30, green: 0.18, blue: 0.88)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)
                                .shadow(color: Color(red: 0.46, green: 0.36, blue: 0.98).opacity(isStopHovered ? 0.85 : 0.55), radius: isStopHovered ? 7 : 4)
                                .scaleEffect(isStopHovered ? 1.06 : 1.0)
                                .animation(.easeOut(duration: 0.15), value: isStopHovered)
                            
                            // White rounded square (Stop icon)
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                        }
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isStopHovered = $0 }
                    .help("Stop and Edit Recording")
                    
                    // 5. Elapsed Duration Time (MM:SS) with Auto-Stop Target indicator
                    HStack(spacing: 5) {
                        Text(formatTime(appState.captureManager.recordingDuration))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(Color.white)
                        
                        if let limit = appState.autoStopDuration {
                            HStack(spacing: 2) {
                                Image(systemName: "timer")
                                    .font(.system(size: 9, weight: .bold))
                                Text(formatTime(limit))
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(Color.blue.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                            .help("Auto-Stop target duration")
                        }
                    }
                    .opacity(appState.isRecordingPaused ? 0.5 : 1.0)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}
