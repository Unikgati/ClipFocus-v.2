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
        
        let newItem = NSMenuItem(title: "New Project", action: #selector(handleMenuNew), keyEquivalent: "n")
        newItem.target = self
        fileMenu.addItem(newItem)
        
        let openItem = NSMenuItem(title: "Open Project or Video...", action: #selector(handleMenuOpen), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        
        // Open Recent
        let recentMenuItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        let recents = appState.recentProjectURLs
        if recents.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Projects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentMenu.addItem(emptyItem)
        } else {
            for url in recents {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(handleOpenRecentProject(_:)), keyEquivalent: "")
                item.representedObject = url
                item.target = self
                recentMenu.addItem(item)
            }
        }
        recentMenuItem.submenu = recentMenu
        fileMenu.addItem(recentMenuItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        let saveItem = NSMenuItem(title: "Save Project", action: #selector(handleMenuSave), keyEquivalent: "s")
        saveItem.target = self
        fileMenu.addItem(saveItem)
        
        let saveAsItem = NSMenuItem(title: "Save Project As...", action: #selector(handleMenuSaveAs), keyEquivalent: "S")
        saveAsItem.target = self
        fileMenu.addItem(saveAsItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
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
    @objc private func handleMenuNew() {
        appState.newProject()
    }
    
    @MainActor
    @objc private func handleMenuOpen() {
        appState.openProjectDialog()
    }
    
    @MainActor
    @objc private func handleMenuSave() {
        appState.saveProject(as: false)
    }
    
    @MainActor
    @objc private func handleMenuSaveAs() {
        appState.saveProject(as: true)
    }
    
    @MainActor
    @objc private func handleOpenRecentProject(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            appState.checkUnsavedChanges { [weak self] in
                self?.appState.loadProject(from: url)
            }
        }
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
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if appState.isDirty && appState.currentView == .editor {
            appState.checkUnsavedChanges {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
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
