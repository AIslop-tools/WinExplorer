import AppKit
import SwiftUI

func dbg(_ msg: String) {
    #if DEBUG
    // C-2: write only in debug builds; use the app's own temp dir, never /tmp directly
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WinExplorer", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let logURL = dir.appendingPathComponent("debug.log")
    let line = (msg + "\n").data(using: .utf8) ?? Data()
    // Cap log at 1 MB — rotate by truncating to last 512 KB when limit is exceeded
    let maxSize: UInt64 = 1_048_576
    if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
       let size = attrs[.size] as? UInt64, size > maxSize,
       let fh = try? FileHandle(forReadingFrom: logURL) {
        fh.seek(toFileOffset: size - 524_288)
        let tail = fh.readDataToEndOfFile()
        fh.closeFile()
        try? tail.write(to: logURL)
    }
    if let fh = try? FileHandle(forWritingTo: logURL) {
        fh.seekToEndOfFile(); fh.write(line); fh.closeFile()
    } else {
        try? line.write(to: logURL)
    }
    #endif
}

NSApplication.shared.setActivationPolicy(.regular)
dbg("A: activation policy set")

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var hostingController: NSHostingController<AnyView>!
    var vm: FileManagerViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        dbg("B: applicationDidFinishLaunching — deferring window to next runloop")
        DispatchQueue.main.async { self.createWindow() }
    }

    func createWindow() {
        dbg("C: createWindow")
        vm = FileManagerViewModel()
        dbg("D: ViewModel created, items=\(vm.items.count)")

        let root = AnyView(ContentView().environmentObject(vm))
        dbg("E: root view built")

        hostingController = NSHostingController(rootView: root)
        dbg("F: hosting controller created")

        window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1000, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WinExplorer"
        window.minSize = NSSize(width: 1000, height: 800)
        window.contentViewController = hostingController
        dbg("G: contentViewController set")

        NSApp.mainMenu = buildMenuBar()

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // C-1: resolve icon relative to the executable, not a hardcoded developer path
        if let exeURL = Bundle.main.executableURL {
            let iconURL = exeURL.deletingLastPathComponent().appendingPathComponent("AppIcon.png")
            if let icon = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = icon
            }
        }
        dbg("H: window shown — frame: \(window.frame)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu Bar

    private func buildMenuBar() -> NSMenu {
        let main = NSMenu()

        // ── App menu ──────────────────────────────────────────────────────────
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "About WinExplorer", action: nil, keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(mi("Hide WinExplorer",  action: #selector(NSApplication.hide(_:)),                    key: "h",  target: NSApp))
        appMenu.addItem(mi("Hide Others",        action: #selector(NSApplication.hideOtherApplications(_:)),  key: "h",  mod: [.command, .option], target: NSApp))
        appMenu.addItem(mi("Show All",           action: #selector(NSApplication.unhideAllApplications(_:)),  key: "",   target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(mi("Quit WinExplorer",   action: #selector(NSApplication.terminate(_:)),              key: "q",  target: NSApp))

        // ── File menu ─────────────────────────────────────────────────────────
        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        fileMenu.addItem(mi("New Folder",        action: #selector(newFolderAction),   key: "N", mod: [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(mi("Open",              action: #selector(openSelectedAction), key: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(mi("Rename",            action: #selector(renameAction),       key: ""))
        fileMenu.addItem(mi("Show in Finder",    action: #selector(showInFinderAction), key: ""))
        fileMenu.addItem(mi("Open Terminal Here",action: #selector(openTerminalAction), key: ""))
        fileMenu.addItem(.separator())
        fileMenu.addItem(mi("Move to Trash",     action: #selector(deleteAction),       key: String(UnicodeScalar(NSBackspaceCharacter)!), mod: .command))
        fileMenu.addItem(.separator())
        fileMenu.addItem(mi("Empty Trash…",      action: #selector(emptyTrashAction),   key: String(UnicodeScalar(NSDeleteCharacter)!),    mod: [.command, .shift]))

        // ── Edit menu ─────────────────────────────────────────────────────────
        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(mi("Cut",        action: #selector(cutAction),       key: "x"))
        editMenu.addItem(mi("Copy",       action: #selector(copyAction),      key: "c"))
        editMenu.addItem(mi("Paste",      action: #selector(pasteAction),     key: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(mi("Select All", action: #selector(selectAllAction), key: "a"))

        // ── View menu ─────────────────────────────────────────────────────────
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        viewMenu.addItem(mi("Large Icons", action: #selector(viewLargeIconsAction), key: "1"))
        viewMenu.addItem(mi("Details",     action: #selector(viewDetailsAction),    key: "2"))
        viewMenu.addItem(.separator())
        let hiddenItem = mi("Show Hidden Files", action: #selector(toggleHiddenAction), key: ".", mod: [.command, .shift])
        viewMenu.addItem(hiddenItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(mi("Refresh",     action: #selector(refreshAction),        key: "r"))

        // ── Go menu ───────────────────────────────────────────────────────────
        let goItem = NSMenuItem(); main.addItem(goItem)
        let goMenu = NSMenu(title: "Go"); goItem.submenu = goMenu
        goMenu.addItem(mi("Back",             action: #selector(goBackAction),        key: "["))
        goMenu.addItem(mi("Forward",          action: #selector(goForwardAction),     key: "]"))
        let upItem = mi("Enclosing Folder",   action: #selector(goUpAction),          key: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        upItem.keyEquivalentModifierMask = .command; goMenu.addItem(upItem)
        goMenu.addItem(.separator())
        goMenu.addItem(mi("Home",             action: #selector(goHomeAction),        key: "H", mod: [.command, .shift]))
        goMenu.addItem(mi("Desktop",          action: #selector(goDesktopAction),     key: "D", mod: [.command, .shift]))
        goMenu.addItem(mi("Downloads",        action: #selector(goDownloadsAction),   key: "L", mod: [.command, .shift]))
        goMenu.addItem(mi("Documents",        action: #selector(goDocumentsAction),   key: "O", mod: [.command, .shift]))
        goMenu.addItem(mi("Applications",     action: #selector(goApplicationsAction),key: "A", mod: [.command, .shift]))
        goMenu.addItem(.separator())
        goMenu.addItem(mi("Connect to Server…", action: #selector(connectToServerAction), key: "k"))

        // ── Window menu ───────────────────────────────────────────────────────
        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "Window"); winItem.submenu = winMenu
        winMenu.addItem(mi("Minimize", action: #selector(NSWindow.miniaturize(_:)), key: "m", target: window))
        winMenu.addItem(mi("Zoom",     action: #selector(NSWindow.zoom(_:)),        key: "",  target: window))
        NSApp.windowsMenu = winMenu

        return main
    }

    // Convenience builder
    private func mi(_ title: String, action: Selector, key: String,
                    mod: NSEvent.ModifierFlags = .command,
                    target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mod
        item.target = target ?? self
        return item
    }

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(cutAction), #selector(copyAction), #selector(deleteAction):
            return !(vm?.selectedItemIDs.isEmpty ?? true)
        case #selector(renameAction), #selector(openSelectedAction), #selector(showInFinderAction):
            return vm?.selectedItemIDs.count == 1
        case #selector(pasteAction):
            return vm?.canPaste ?? false
        case #selector(emptyTrashAction):
            return !(vm?.items.isEmpty ?? true)
        case #selector(goBackAction):
            return vm?.canGoBack ?? false
        case #selector(goForwardAction):
            return vm?.canGoForward ?? false
        case #selector(goUpAction):
            return vm?.canGoUp ?? false
        case #selector(viewLargeIconsAction):
            menuItem.state = vm?.viewMode == .largeIcons ? .on : .off
            return true
        case #selector(viewDetailsAction):
            menuItem.state = vm?.viewMode == .details ? .on : .off
            return true
        case #selector(toggleHiddenAction):
            menuItem.state = vm?.showHiddenFiles == true ? .on : .off
            return true
        default:
            return true
        }
    }

    // MARK: - File actions
    @objc func newFolderAction()     { vm?.newFolder() }
    @objc func openSelectedAction()  { vm?.openSelected() }
    @objc func renameAction()        { vm?.beginRename() }
    @objc func deleteAction()        { vm?.deleteSelected() }
    @objc func showInFinderAction()  { if let item = vm?.selectedItems.first { vm?.showInFinder(item) } }
    @objc func openTerminalAction()  { vm?.openTerminal() }
    @objc func emptyTrashAction()    { vm?.emptyTrash() }

    // MARK: - Edit actions
    @objc func cutAction()           { vm?.cutSelected() }
    @objc func copyAction()          { vm?.copySelected() }
    @objc func pasteAction()         { vm?.paste() }
    @objc func selectAllAction()     { vm?.selectAll() }

    // MARK: - View actions
    @objc func viewLargeIconsAction(){ vm?.viewMode = .largeIcons }
    @objc func viewDetailsAction()   { vm?.viewMode = .details }
    @objc func toggleHiddenAction()  { vm?.showHiddenFiles.toggle() }
    @objc func refreshAction()       { vm?.loadItems() }

    // MARK: - Go actions
    @objc func goBackAction()        { vm?.goBack() }
    @objc func goForwardAction()     { vm?.goForward() }
    @objc func goUpAction()          { vm?.goUp() }
    @objc func goHomeAction()        { vm?.navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
    @objc func goDesktopAction()     { nav(.desktopDirectory) }
    @objc func goDownloadsAction()   { nav(.downloadsDirectory) }
    @objc func goDocumentsAction()   { nav(.documentDirectory) }
    @objc func goApplicationsAction(){ vm?.navigate(to: URL(fileURLWithPath: "/Applications")) }

    @objc func connectToServerAction() { vm?.showConnectToServerDialog() }

    private func nav(_ dir: FileManager.SearchPathDirectory) {
        if let url = FileManager.default.urls(for: dir, in: .userDomainMask).first {
            vm?.navigate(to: url)
        }
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
dbg("I: about to run NSApp")
NSApplication.shared.run()
