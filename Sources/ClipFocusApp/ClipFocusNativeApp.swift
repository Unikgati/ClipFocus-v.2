import SwiftUI
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var strongDelegate: AppDelegate?
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        strongDelegate = delegate
        app.delegate = delegate
        app.run()
    }
    
    let appState = AppState()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSLog("ClipFocus CommandLine.arguments: %@", CommandLine.arguments)
        if CommandLine.arguments.contains("--permissions") {
            appState.showPermissionsWindow = true
        }
        if let modeArg = CommandLine.arguments.first(where: { $0.starts(with: "--mode=") }) {
            let modeStr = modeArg.replacingOccurrences(of: "--mode=", with: "").lowercased()
            switch modeStr {
            case "fullscreen":
                appState.selectMode(.fullScreen)
            case "custom":
                appState.selectMode(.custom)
            case "window":
                appState.selectMode(.window)
            default:
                break
            }
        }
        WindowManager.shared.start(with: appState)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NSLog("ClipFocusApp applicationWillTerminate called! Callstack:\n%@", Thread.callStackSymbols.joined(separator: "\n"))
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            appState.currentView = .launcher
            WindowManager.shared.updateWindows()
        }
        return true
    }
}
