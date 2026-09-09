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
        if let editArg = CommandLine.arguments.first(where: { $0.starts(with: "--edit=") }) {
            let path = editArg.replacingOccurrences(of: "--edit=", with: "")
            let url = URL(fileURLWithPath: path)
            appState.loadRecordedVideo(url: url)
        } else if let editIdx = CommandLine.arguments.firstIndex(of: "--edit"), editIdx + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[editIdx + 1]
            let url = URL(fileURLWithPath: path)
            appState.loadRecordedVideo(url: url)
        }
        setupMenuBar()
        WindowManager.shared.start(with: appState)
    }
    
    private func setupMenuBar() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ClipFocus", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit ClipFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let exportItem = NSMenuItem(title: "Export Video...", action: #selector(handleMenuExport), keyEquivalent: "e")
        exportItem.target = self
        fileMenu.addItem(exportItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undoItem = NSMenuItem(title: "Undo", action: #selector(handleMenuUndo), keyEquivalent: "z")
        undoItem.target = self
        editMenu.addItem(undoItem)
        let redoItem = NSMenuItem(title: "Redo", action: #selector(handleMenuRedo), keyEquivalent: "Z")
        redoItem.target = self
        editMenu.addItem(redoItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @MainActor
    @objc private func handleMenuExport() {
        appState.exportVideo()
    }
    
    @MainActor
    @objc private func handleMenuUndo() {
        appState.undo()
    }
    
    @MainActor
    @objc private func handleMenuRedo() {
        appState.redo()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if appState.hideDesktopIcons {
            appState.hideDesktopIcons = false
        }
        NSLog("ClipFocusApp applicationWillTerminate called!")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            appState.currentView = .launcher
            WindowManager.shared.updateWindows()
        }
        return true
    }
}
