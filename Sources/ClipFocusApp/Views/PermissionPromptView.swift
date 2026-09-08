import SwiftUI
import AppKit

public struct PermissionPromptView: View {
    public let onDismiss: () -> Void
    public let onCheckAgain: () -> Void
    
    public init(onDismiss: @escaping () -> Void, onCheckAgain: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.onCheckAgain = onCheckAgain
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.and.keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.cyan)
                .padding(.top, 10)
            
            VStack(spacing: 6) {
                Text("Screen Recording Permission Required")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("macOS requires explicit permission for ClipFocus to capture your screen, windows, and mouse interactions.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("1.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("Click 'Open System Settings' below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    Text("2.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("Turn on the toggle next to ClipFocus in Screen Recording.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            HStack(spacing: 12) {
                Button("Cancel", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
                
                Button("Check Permission") {
                    onCheckAgain()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(28)
        .background(Color(red: 0.12, green: 0.14, blue: 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(radius: 30)
        .frame(width: 520)
    }
}
