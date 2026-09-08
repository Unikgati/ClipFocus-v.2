import SwiftUI
import AppKit

public struct WindowAccessor: NSViewRepresentable {
    public var configure: (NSWindow) -> Void
    
    public init(configure: @escaping (NSWindow) -> Void) {
        self.configure = configure
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.configure(window)
            }
        }
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            self.configure(window)
        }
    }
}
