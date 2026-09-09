import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

/// 100% pixel-perfect implementation of FocuSee's "Enable System Permissions" window
public struct PermissionsModalView: View {
    @Bindable var appState: AppState
    public let onDismiss: () -> Void
    
    @State private var hasScreenAccess: Bool = false
    @State private var hasMicAccess: Bool = false
    @State private var hasAccessibilityAccess: Bool = false
    
    @State private var pollTimer: Timer?
    
    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header: Title & Subtitle with clearance for native red close button (Y = 16)
            VStack(spacing: 8) {
                Text("Enable System Permissions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Due to the privacy policy of macOS, the following permissions need to be\nenabled for ClipFocus to record properly.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(white: 0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 480)
            }
            .padding(.top, 30)
            .padding(.bottom, 26)
            
            // 3 Permission rows
            VStack(spacing: 16) {
                // 1. Screen Access
                permissionRow(
                    iconName: "viewfinder",
                    title: "Allow screen access to record your screen and system sound",
                    isEnabled: hasScreenAccess,
                    onEnable: {
                        _ = CGRequestScreenCaptureAccess()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                
                // 2. Microphone Access
                permissionRow(
                    iconName: "mic.fill",
                    title: "Allow ClipFocus to access the microphone to record your voice",
                    isEnabled: hasMicAccess,
                    onEnable: {
                        let status = AVCaptureDevice.authorizationStatus(for: .audio)
                        if status == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async {
                                    hasMicAccess = granted
                                    checkAllPermissions()
                                }
                            }
                        } else {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                )
                
                // 4. Accessibility (Key click tracking)
                permissionRow(
                    iconName: "hand.raised.fill",
                    title: "Allow ClipFocus to capture shortcut key clicks during recording",
                    isEnabled: hasAccessibilityAccess,
                    onEnable: {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Bottom Confirm Button
            Button(action: onDismiss) {
                Text("Confirm")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 140, height: 34)
                    .background(Color(red: 0.11, green: 0.13, blue: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 22)
        }
        .frame(width: 620, height: 410)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
        .ignoresSafeArea()
        .onAppear {
            checkAllPermissions()
            startPeriodicCheck()
        }
        .onDisappear {
            stopPeriodicCheck()
        }
    }
    
    @ViewBuilder
    private func permissionRow(
        iconName: String,
        title: String,
        isEnabled: Bool,
        onEnable: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            // Icon Square
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.14, green: 0.16, blue: 0.21))
                    .frame(width: 36, height: 36)
                
                Image(systemName: iconName)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            }
            
            // Description Text
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 16)
            
            // Action Button or Enabled Status
            if isEnabled {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Enabled")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.18, green: 0.78, blue: 0.45))
                .frame(width: 84, alignment: .trailing)
            } else {
                Button(action: onEnable) {
                    Text("Enable")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 30)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.25, green: 0.45, blue: 1.0), Color(red: 0.65, green: 0.35, blue: 1.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func checkAllPermissions() {
        hasScreenAccess = CGPreflightScreenCaptureAccess()
        hasMicAccess = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        hasAccessibilityAccess = AXIsProcessTrusted()
        
        // Synchronize with appState
        appState.checkPermissions()
    }
    
    private func startPeriodicCheck() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.checkAllPermissions()
            }
        }
    }
    
    private func stopPeriodicCheck() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
