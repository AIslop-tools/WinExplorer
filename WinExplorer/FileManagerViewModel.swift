import Foundation
import AppKit
import Combine
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case largeIcons = "Large Icons"
    case details = "Details"
    var id: String { rawValue }
}

enum SortField: String {
    case name, dateModified, type, size
}

struct BreadcrumbItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

struct SidebarSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [SidebarItem]
}

struct SidebarItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let systemImage: String
    var isNetworkVolume: Bool = false
}

struct ViewModelKey: FocusedValueKey {
    typealias Value = FileManagerViewModel
}

extension FocusedValues {
    var fileManagerViewModel: FileManagerViewModel? {
        get { self[ViewModelKey.self] }
        set { self[ViewModelKey.self] = newValue }
    }
}

class FileManagerViewModel: ObservableObject {
    @Published var currentURL: URL
    @Published var items: [FileItem] = []
    @Published var selectedItemIDs: Set<UUID> = []
    private(set) var historyStack: [URL] = []
    private(set) var historyIndex: Int = -1
    @Published var viewMode: ViewMode = .details
    @Published var sortField: SortField = .name
    @Published var sortAscending: Bool = true
    @Published var searchText: String = "" {
        didSet { applyFilter() }
    }
    @Published var statusMessage: String = ""
    @Published var renamingItemID: UUID? = nil
    @Published var sidebarSections: [SidebarSection] = []
    @Published var breadcrumbs: [BreadcrumbItem] = []
    @Published var showHiddenFiles: Bool = false {
        didSet { loadItems() }
    }

    private var allItems: [FileItem] = []
    private var clipboardURLs: [URL] = []
    private var clipboardIsCut: Bool = false
    private let fm = FileManager.default
    private var volumeObservers: [Any] = []

    init() {
        self.currentURL = fm.homeDirectoryForCurrentUser
        buildSidebarSections()
        navigate(to: fm.homeDirectoryForCurrentUser, addToHistory: true)
        setupVolumeNotifications()
    }

    private func setupVolumeNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        let rebuild: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.buildSidebarSections() }
        }
        volumeObservers.append(nc.addObserver(forName: NSWorkspace.didMountNotification,   object: nil, queue: nil, using: rebuild))
        volumeObservers.append(nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: nil, using: rebuild))
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in volumeObservers { nc.removeObserver(obs) }
    }

    func connectToServer(_ urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty && !s.contains("://") { s = "smb://" + s }
        guard !s.isEmpty, let url = URL(string: s) else { return }
        let allowed = ["smb", "afp", "nfs", "ftp", "ftps"]
        guard let scheme = url.scheme?.lowercased(), allowed.contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    func showConnectToServerDialog() {
        let alert = NSAlert()
        alert.messageText = "Connect to Server"
        alert.informativeText = "Enter the server address (SMB, AFP, NFS, or FTP):"
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        field.placeholderString = "smb://server/share  or  192.168.1.10"
        field.font = NSFont.systemFont(ofSize: 13)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        connectToServer(input)
    }

    func disconnectVolume(_ url: URL) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Disconnect"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Navigation

    func navigate(to url: URL, addToHistory: Bool = true) {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }

        if addToHistory {
            if historyIndex < historyStack.count - 1 {
                historyStack = Array(historyStack.prefix(historyIndex + 1))
            }
            historyStack.append(url)
            historyIndex = historyStack.count - 1
        }
        currentURL = url
        loadItems()
    }

    func goBack() {
        guard canGoBack, historyStack.indices.contains(historyIndex - 1) else { return }
        historyIndex -= 1
        currentURL = historyStack[historyIndex]
        loadItems()
    }

    func goForward() {
        guard canGoForward, historyStack.indices.contains(historyIndex + 1) else { return }
        historyIndex += 1
        currentURL = historyStack[historyIndex]
        loadItems()
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        navigate(to: parent)
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < historyStack.count - 1 }
    var canGoUp: Bool { currentURL.path != "/" }

    // MARK: - Loading

    func loadItems() {
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : .skipsHiddenFiles
        let contents = (try? fm.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: options
        )) ?? []
        allItems = contents.map { FileItem(url: $0) }
        sortItems()
        applyFilter()
        updateStatus()
        rebuildBreadcrumbs()
    }

    private func rebuildBreadcrumbs() {
        var result: [BreadcrumbItem] = []
        var url = currentURL
        var depth = 0
        while depth < 50 {
            depth += 1
            result.append(BreadcrumbItem(name: breadcrumbName(for: url), url: url))
            if url.path == "/" { break }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        breadcrumbs = result.reversed()
    }

    private func sortItems() {
        allItems.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: Bool
            switch sortField {
            case .name:
                result = a.name.localizedCompare(b.name) == .orderedAscending
            case .dateModified:
                result = (a.modificationDate ?? .distantPast) < (b.modificationDate ?? .distantPast)
            case .type:
                result = a.fileType.localizedCompare(b.fileType) == .orderedAscending
            case .size:
                result = (a.fileSize ?? 0) < (b.fileSize ?? 0)
            }
            return sortAscending ? result : !result
        }
    }

    private func applyFilter() {
        if searchText.isEmpty {
            items = allItems
        } else {
            items = allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        updateStatus()
    }

    // MARK: - Sorting

    func sortBy(_ field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
        sortItems()
        applyFilter()
    }

    // MARK: - Selection

    var selectedItems: [FileItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    func selectAll() {
        selectedItemIDs = Set(items.map { $0.id })
        updateStatus()
    }

    func clearSelection() {
        selectedItemIDs = []
        updateStatus()
    }

    private func updateStatus() {
        let count = items.count
        let selCount = selectedItemIDs.count
        if selCount == 0 {
            statusMessage = "\(count) item\(count == 1 ? "" : "s")"
        } else {
            let selSize = selectedItems.filter { !$0.isDirectory }.compactMap { $0.fileSize }.reduce(0, +)
            if selSize > 0 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: selSize, countStyle: .file)
                statusMessage = "\(selCount) item\(selCount == 1 ? "" : "s") selected (\(sizeStr))"
            } else {
                statusMessage = "\(selCount) item\(selCount == 1 ? "" : "s") selected"
            }
        }
    }

    // MARK: - File Operations

    func openItem(_ item: FileItem) {
        if item.isDirectory {
            navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openSelected() {
        for item in selectedItems { openItem(item) }
    }

    func deleteSelected() {
        guard !selectedItems.isEmpty else { return }
        let count = selectedItems.count
        let name = selectedItems.first?.name ?? ""
        let msg = count == 1
            ? "Are you sure you want to move '\(name)' to the Trash?"
            : "Are you sure you want to move these \(count) items to the Trash?"

        let alert = NSAlert()
        alert.messageText = "Delete"
        alert.informativeText = msg
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            var failures: [String] = []
            for item in selectedItems {
                do { try fm.trashItem(at: item.url, resultingItemURL: nil) }
                catch { failures.append(item.name) }
            }
            loadItems()
            if !failures.isEmpty {
                let err = NSAlert()
                err.messageText = "Could Not Move to Trash"
                err.informativeText = failures.joined(separator: "\n")
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    func newFolder() {
        var name = "New folder"
        var counter = 2
        var url = currentURL.appendingPathComponent(name)
        while fm.fileExists(atPath: url.path) {
            name = "New folder (\(counter))"
            url = currentURL.appendingPathComponent(name)
            counter += 1
        }
        guard (try? fm.createDirectory(at: url, withIntermediateDirectories: false)) != nil else { return }
        loadItems()
        if let newItem = items.first(where: { $0.url == url }) {
            selectedItemIDs = [newItem.id]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.renamingItemID = newItem.id
            }
        }
    }

    func beginRename() {
        guard selectedItems.count == 1 else { return }
        renamingItemID = selectedItems[0].id
    }

    func commitRename(item: FileItem, newName: String) {
        renamingItemID = nil
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        // C-3: block path traversal — names must not contain separators or null bytes
        guard !trimmed.contains("/"), !trimmed.contains("\0") else { return }
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        // M-10: warn if destination already exists
        guard !fm.fileExists(atPath: newURL.path) else {
            let alert = NSAlert()
            alert.messageText = "Name Already Taken"
            alert.informativeText = "\"\(trimmed)\" already exists in this folder."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        do {
            try fm.moveItem(at: item.url, to: newURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Rename"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
        loadItems()
    }

    func cancelRename() {
        renamingItemID = nil
    }

    func copySelected() {
        guard !selectedItems.isEmpty else { return }
        clipboardURLs = selectedItems.map { $0.url }
        clipboardIsCut = false
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(clipboardURLs.map { $0 as NSURL })
    }

    func cutSelected() {
        guard !selectedItems.isEmpty else { return }
        clipboardURLs = selectedItems.map { $0.url }
        clipboardIsCut = true
    }

    func paste() {
        var urlsToPaste = clipboardURLs
        if urlsToPaste.isEmpty {
            urlsToPaste = (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        }
        // H-1: only accept file URLs that exist
        urlsToPaste = urlsToPaste.filter { $0.isFileURL && fm.fileExists(atPath: $0.path) }
        guard !urlsToPaste.isEmpty else { return }

        for url in urlsToPaste {
            let dest = uniqueDestinationURL(for: url, in: currentURL)
            if clipboardIsCut {
                try? fm.moveItem(at: url, to: dest)
            } else {
                try? fm.copyItem(at: url, to: dest)
            }
        }
        if clipboardIsCut {
            clipboardURLs = []
            clipboardIsCut = false
        }
        loadItems()
    }

    var canPaste: Bool {
        !clipboardURLs.isEmpty
    }

    private func uniqueDestinationURL(for source: URL, in directory: URL) -> URL {
        var dest = directory.appendingPathComponent(source.lastPathComponent)
        guard fm.fileExists(atPath: dest.path) else { return dest }
        var counter = 2
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        // M-8: cap at 1000 iterations to prevent infinite loop
        while counter <= 1000 {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            dest = directory.appendingPathComponent(newName)
            if !fm.fileExists(atPath: dest.path) { return dest }
            counter += 1
        }
        // Fallback: use a UUID suffix
        let uuid = UUID().uuidString.prefix(8)
        let fallback = ext.isEmpty ? "\(base)-\(uuid)" : "\(base)-\(uuid).\(ext)"
        return directory.appendingPathComponent(fallback)
    }

    func showInFinder(_ item: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func getInfo(_ item: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openTerminal() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", currentURL.path]
        try? task.run()
    }

    // MARK: - Breadcrumb

    private func breadcrumbName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        if url.path == fm.homeDirectoryForCurrentUser.path { return "Home" }
        return url.lastPathComponent
    }

    // MARK: - Sidebar

    private func buildSidebarSections() {
        var sections: [SidebarSection] = []

        let quickItems: [(String, URL?, String)] = [
            ("Desktop",   fm.urls(for: .desktopDirectory,   in: .userDomainMask).first, "menubar.dock.rectangle"),
            ("Downloads", fm.urls(for: .downloadsDirectory, in: .userDomainMask).first, "arrow.down.circle"),
            ("Documents", fm.urls(for: .documentDirectory,  in: .userDomainMask).first, "doc"),
            ("Pictures",  fm.urls(for: .picturesDirectory,  in: .userDomainMask).first, "photo"),
            ("Music",     fm.urls(for: .musicDirectory,     in: .userDomainMask).first, "music.note"),
            ("Movies",    fm.urls(for: .moviesDirectory,    in: .userDomainMask).first, "film"),
        ]
        sections.append(SidebarSection(title: "Quick access", items: quickItems.compactMap { name, url, img in
            guard let url = url else { return nil }
            return SidebarItem(name: name, url: url, systemImage: img)
        }))

        sections.append(SidebarSection(title: "This Mac", items: [
            SidebarItem(name: "Home", url: fm.homeDirectoryForCurrentUser, systemImage: "house"),
            SidebarItem(name: "Macintosh HD", url: URL(fileURLWithPath: "/"), systemImage: "internaldrive"),
        ]))

        let volumes = (try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: [.volumeIsLocalKey, .volumeIsRemovableKey],
            options: .skipsHiddenFiles
        )) ?? []

        var localVols: [SidebarItem] = []
        var networkVols: [SidebarItem] = []
        for url in volumes {
            let res = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
            let isLocal = res?.volumeIsLocal ?? true
            if isLocal {
                localVols.append(SidebarItem(name: url.lastPathComponent, url: url, systemImage: "externaldrive"))
            } else {
                networkVols.append(SidebarItem(name: url.lastPathComponent, url: url, systemImage: "network", isNetworkVolume: true))
            }
        }

        if !localVols.isEmpty {
            sections.append(SidebarSection(title: "Devices & Drives", items: localVols))
        }
        if !networkVols.isEmpty {
            sections.append(SidebarSection(title: "Network Drives", items: networkVols))
        }

        sidebarSections = sections
    }
}
