import SwiftUI
import AppKit
import ScreenCaptureKit

// MARK: - Native macOS Resize Cursor Helpers
public struct CustomCursorHelper {
    public static let nwseCursor: NSCursor = {
        let sel = Selector(("_windowResizeNorthWestSouthEastCursor"))
        if NSCursor.responds(to: sel), let res = NSCursor.perform(sel) {
            return res.takeUnretainedValue() as! NSCursor
        }
        return NSCursor.crosshair
    }()
    
    public static let neswCursor: NSCursor = {
        let sel = Selector(("_windowResizeNorthEastSouthWestCursor"))
        if NSCursor.responds(to: sel), let res = NSCursor.perform(sel) {
            return res.takeUnretainedValue() as! NSCursor
        }
        return NSCursor.crosshair
    }()
}

public struct RecordingAreaOverlayView: View {
    @Bindable var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            
            ZStack {
                switch appState.selectedMode {
                case .fullScreen:
                    fullScreenOverlay(screenSize: screenSize)
                    
                case .custom:
                    customCropOverlay(screenSize: screenSize)
                    
                case .window:
                    windowSelectionOverlay(screenSize: screenSize)
                    
                case .none:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 1. Full Screen Overlay (Pure dashed perimeter)
    @ViewBuilder
    private func fullScreenOverlay(screenSize: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                Color(red: 0.05, green: 0.80, blue: 1.0),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round, dash: [14, 8])
            )
            .padding(4)
            .allowsHitTesting(false)
    }
    
    // MARK: - 2. Custom Crop Area Overlay (8 handles, dimension badge, 100% native tracking)
    @ViewBuilder
    private func customCropOverlay(screenSize: CGSize) -> some View {
        let crop = appState.customCropRect
        
        ZStack {
            // A. Dimmed outer mask with cut-out hole
            Path { path in
                path.addRect(CGRect(origin: .zero, size: screenSize))
                path.addRect(crop)
            }
            .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            
            // B. Dashed Cyan Border
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    Color(red: 0.05, green: 0.80, blue: 1.0),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [10, 6])
                )
                .frame(width: crop.width, height: crop.height)
                .position(x: crop.midX, y: crop.midY)
                .allowsHitTesting(false)
            
            // C. 4 Edge Handle indicators (center pill on each side)
            // Top Edge
            Capsule()
                .fill(Color.white)
                .overlay(Capsule().stroke(Color(red: 0.05, green: 0.80, blue: 1.0), lineWidth: 1.5))
                .frame(width: 24, height: 5)
                .shadow(color: Color.black.opacity(0.4), radius: 2)
                .position(x: crop.midX, y: crop.minY)
                .allowsHitTesting(false)
            
            // Bottom Edge
            Capsule()
                .fill(Color.white)
                .overlay(Capsule().stroke(Color(red: 0.05, green: 0.80, blue: 1.0), lineWidth: 1.5))
                .frame(width: 24, height: 5)
                .shadow(color: Color.black.opacity(0.4), radius: 2)
                .position(x: crop.midX, y: crop.maxY)
                .allowsHitTesting(false)
                
            // Left Edge
            Capsule()
                .fill(Color.white)
                .overlay(Capsule().stroke(Color(red: 0.05, green: 0.80, blue: 1.0), lineWidth: 1.5))
                .frame(width: 5, height: 24)
                .shadow(color: Color.black.opacity(0.4), radius: 2)
                .position(x: crop.minX, y: crop.midY)
                .allowsHitTesting(false)
                
            // Right Edge
            Capsule()
                .fill(Color.white)
                .overlay(Capsule().stroke(Color(red: 0.05, green: 0.80, blue: 1.0), lineWidth: 1.5))
                .frame(width: 5, height: 24)
                .shadow(color: Color.black.opacity(0.4), radius: 2)
                .position(x: crop.maxX, y: crop.midY)
                .allowsHitTesting(false)
            
            // D. 4 Corner Resize Handles
            cornerCircle(position: CGPoint(x: crop.minX, y: crop.minY))
            cornerCircle(position: CGPoint(x: crop.maxX, y: crop.minY))
            cornerCircle(position: CGPoint(x: crop.minX, y: crop.maxY))
            cornerCircle(position: CGPoint(x: crop.maxX, y: crop.maxY))
            
            // E. Dimension Badge (e.g. 800 × 500 px)
            HStack(spacing: 4) {
                Text("\(Int(crop.width)) × \(Int(crop.height)) px")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.88))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.4), radius: 3)
            .position(x: crop.midX, y: crop.minY > 40 ? crop.minY - 20 : crop.minY + 24)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func cornerCircle(position: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color(red: 0.05, green: 0.80, blue: 1.0), lineWidth: 2.5))
            .shadow(color: Color.black.opacity(0.45), radius: 2)
            .position(x: position.x, y: position.y)
            .allowsHitTesting(false)
    }
    
    // MARK: - 3. Window Selection Overlay (Render active or hovered window outline)
    @ViewBuilder
    private func windowSelectionOverlay(screenSize: CGSize) -> some View {
        let activeFrame = appState.selectedWindowFrame ?? appState.hoveredWindowFrame
        
        ZStack {
            if let frame = activeFrame {
                let primaryH = NSScreen.screens.first?.frame.height ?? 1080
                // Match screen housing the window
                let targetScreen = NSScreen.screens.first(where: { screen in
                    let qX = screen.frame.origin.x
                    let qY = primaryH - (screen.frame.origin.y + screen.frame.height)
                    let screenQRect = CGRect(x: qX, y: qY, width: screen.frame.width, height: screen.frame.height)
                    return screenQRect.intersects(frame)
                }) ?? NSScreen.screens.first
                
                let pScreen = targetScreen ?? NSScreen.screens[0]
                let panelQuartzX = pScreen.frame.origin.x
                let panelQuartzY = primaryH - (pScreen.frame.origin.y + pScreen.frame.height)
                
                let localX = frame.origin.x - panelQuartzX
                let localY = frame.origin.y - panelQuartzY
                
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        Color(red: 0.05, green: 0.80, blue: 1.0),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [14, 8])
                    )
                    .background(Color(red: 0.05, green: 0.80, blue: 1.0).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: localX + frame.width / 2, y: localY + frame.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}
