import Foundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

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
    var isEjectable: Bool = false   // true for network volumes, removable drives, and disk images
    var isRecents: Bool = false     // sentinel: clicking this shows the Recents Spotlight view
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
    @Published var isShowingRecents: Bool = false

    private var allItems: [FileItem] = []
    private var clipboardURLs: [URL] = []
    private var clipboardIsCut: Bool = false
    private let fm = FileManager.default
    private var volumeObservers: [Any] = []
    private var metadataQuery: NSMetadataQuery?

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
        metadataQuery?.stop()
        let nc = NSWorkspace.shared.notificationCenter
        for obs in volumeObservers { nc.removeObserver(obs) }
    }

    // MARK: - Recents (Spotlight)

    func showRecents() {
        isShowingRecents = true
        selectedItemIDs = []
        breadcrumbs = [BreadcrumbItem(name: "Recents", url: fm.homeDirectoryForCurrentUser)]

        metadataQuery?.stop()
        let q = NSMetadataQuery()
        // Files opened in the last 30 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())! as NSDate
        q.predicate = NSPredicate(format: "%K > %@", NSMetadataItemLastUsedDateKey, cutoff)
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        q.searchScopes = [NSMetadataQueryLocalComputerScope]

        // Use a box so the closure can reference the observer token without a mutation-after-capture warning
        let box = Box<NSObjectProtocol?>()
        box.value = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            self?.handleQueryResults(q)
            if let obs = box.value { NotificationCenter.default.removeObserver(obs as Any) }
        }
        metadataQuery = q
        q.start()

        // Show a loading placeholder while the query runs
        items = []
        updateStatus()
    }

    private func handleQueryResults(_ q: NSMetadataQuery) {
        q.disableUpdates()
        var seen = Set<String>()
        var result: [FileItem] = []
        for i in 0 ..< q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.contains("/."), !path.hasPrefix("/private/"),
                  !path.hasPrefix("/System/"), !path.hasPrefix("/usr/"),
                  seen.insert(path).inserted else { continue }
            result.append(FileItem(url: URL(fileURLWithPath: path)))
            if result.count == 200 { break }
        }
        q.enableUpdates()
        allItems = result
        applyFilter()
        updateStatus()
    }

    func connectToServer(_ urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty && !s.contains("://") { s = "smb://" + s }
        guard !s.isEmpty, let url = URL(string: s) else { return }
        let allowed = ["smb", "afp", "nfs", "ftp", "ftps"]
        guard let scheme = url.scheme?.lowercased(), allowed.contains(scheme) else { return }
        // Reject embedded credentials (user:pass@host) — pass them via the OS dialog instead
        guard url.user == nil, url.password == nil else {
            let alert = NSAlert()
            alert.messageText = "Credentials Not Allowed in URL"
            alert.informativeText = "For security, enter the server address without a username or password. macOS will prompt for credentials when connecting."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
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
            alert.messageText = "Could Not Eject"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Drag & Drop

    /// URLs being dragged — set when a drag begins so multi-selection moves work correctly.
    var draggedURLs: [URL] = []

    /// Called when a drag starts on `item`. If the item is part of the current
    /// selection, all selected URLs are captured so a drop can move them all.
    func beginDrag(for item: FileItem) {
        if selectedItemIDs.contains(item.id) {
            draggedURLs = selectedItems.map { $0.url }
        } else {
            selectedItemIDs = [item.id]
            draggedURLs = [item.url]
        }
    }

    /// Resolves file URLs from `providers`, then moves (same folder → destination)
    /// or copies (cross-folder / external app) each file into `destinationURL`.
    @discardableResult
    func performDrop(providers: [NSItemProvider], into destinationURL: URL) -> Bool {
        guard destinationURL != currentURL ||
              providers.count > 0 else { return false }

        // Prefer the in-app draggedURLs list for multi-selection moves;
        // fall back to provider URLs for drops from external apps.
        let inAppURLs = draggedURLs.filter { fm.fileExists(atPath: $0.path) }
        draggedURLs = []

        if !inAppURLs.isEmpty {
            applyDrop(urls: inAppURLs, into: destinationURL)
            return true
        }

        // External drop — load URLs asynchronously from providers
        let group = DispatchGroup()
        var externalURLs: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                var resolved: URL?
                if let d = data as? Data {
                    resolved = URL(dataRepresentation: d, relativeTo: nil)
                } else if let u = data as? URL {
                    resolved = u
                }
                if let u = resolved, u.isFileURL {
                    lock.lock(); externalURLs.append(u); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            // Snapshot the array after all providers have resolved (group guarantees completion)
            let snapshot = externalURLs
            self?.applyDrop(urls: snapshot, into: destinationURL)
        }
        return true
    }

    private func applyDrop(urls: [URL], into destinationURL: URL) {
        var failures: [String] = []
        for url in urls {
            let sourceDir = url.deletingLastPathComponent()
            if sourceDir.path == destinationURL.path { continue }  // already there
            let dest = uniqueDestinationURL(for: url, in: destinationURL)
            do {
                // Move if source is within this session's drag (same volume); copy otherwise
                if sourceDir.volumeMountPoint == destinationURL.volumeMountPoint {
                    try fm.moveItem(at: url, to: dest)
                } else {
                    try fm.copyItem(at: url, to: dest)
                }
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        loadItems()
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Could Not Move Some Items"
            alert.informativeText = failures.joined(separator: "\n")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Returns true when a FileItem represents a mounted volume that can be ejected
    /// (disk images, USB drives, optical discs, or network mounts).
    func isEjectableVolume(_ item: FileItem) -> Bool {
        guard item.isDirectory,
              item.url.deletingLastPathComponent().path == "/Volumes" else { return false }
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        guard let res = try? item.url.resourceValues(forKeys: keys) else { return false }
        let isLocal     = res.volumeIsLocal    ?? true
        let isRemovable = res.volumeIsRemovable ?? false
        let isOptical   = res.volumeIsEjectable ?? false
        return !isLocal || isRemovable || isOptical
    }

    // MARK: - Navigation

    func navigate(to url: URL, addToHistory: Bool = true) {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }

        isShowingRecents = false
        metadataQuery?.stop()

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
            let selSize = selectedItems.filter { !$0.isDirectory }
                .compactMap { $0.fileSize }
                .reduce(Int64(0)) { (acc, val) in acc.addingReportingOverflow(val).overflow ? Int64.max : acc + val }
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
        guard fm.isWritableFile(atPath: currentURL.path) else {
            let alert = NSAlert()
            alert.messageText = "Cannot Create Folder"
            alert.informativeText = "You don't have permission to create folders here."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
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
        // Block path traversal: no separators, null bytes, dot-only names, or ".." components
        guard !trimmed.contains("/"), !trimmed.contains("\0"),
              trimmed != ".", trimmed != "..",
              !trimmed.hasPrefix("../"), !trimmed.contains("/../") else { return }
        // Confirm parent dir is writable before attempting rename
        let parentPath = item.url.deletingLastPathComponent().path
        guard fm.isWritableFile(atPath: parentPath) else {
            let alert = NSAlert()
            alert.messageText = "Cannot Rename"
            alert.informativeText = "You don't have permission to rename items in this folder."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
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
        // H-1: only accept file URLs that actually exist on disk
        urlsToPaste = urlsToPaste.filter { $0.isFileURL && fm.fileExists(atPath: $0.path) }
        guard !urlsToPaste.isEmpty else { return }

        // Confirm the current directory is writable before doing anything
        guard fm.isWritableFile(atPath: currentURL.path) else {
            let alert = NSAlert()
            alert.messageText = "Cannot Paste Here"
            alert.informativeText = "You don't have permission to add items to this folder."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        var failures: [String] = []
        for url in urlsToPaste {
            let dest = uniqueDestinationURL(for: url, in: currentURL)
            do {
                if clipboardIsCut {
                    try fm.moveItem(at: url, to: dest)
                } else {
                    try fm.copyItem(at: url, to: dest)
                }
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        if clipboardIsCut {
            clipboardURLs = []
            clipboardIsCut = false
        }
        loadItems()
        if !failures.isEmpty {
            let err = NSAlert()
            err.messageText = "Could Not Paste Some Items"
            err.informativeText = failures.joined(separator: "\n")
            err.alertStyle = .warning
            err.runModal()
        }
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

    // MARK: - SHA-256

    /// Computes the SHA-256 hash of `item` on a background thread, then presents
    /// a results dialog with a one-click Copy button. Shows a progress sheet while working.
    func calculateSHA256(for item: FileItem) {
        guard !item.isDirectory else { return }

        // ── Progress sheet ────────────────────────────────────────────────
        let progress = NSAlert()
        progress.messageText = "Calculating SHA-256…"
        progress.informativeText = item.name
        progress.addButton(withTitle: "Cancel")

        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        progress.accessoryView = indicator

        // Run the hash in the background while the sheet is shown
        var cancelled = false
        let progressWindow: NSWindow = progress.window

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let result = self.sha256(fileURL: item.url, cancelled: { cancelled })

            DispatchQueue.main.async {
                // Dismiss the progress sheet
                progressWindow.close()
                NSApp.stopModal()
                guard !cancelled else { return }

                switch result {
                case .success(let hash):
                    self.showHashResult(hash: hash, item: item)
                case .failure(let error):
                    let err = NSAlert()
                    err.messageText = "Could Not Compute Hash"
                    err.informativeText = error.localizedDescription
                    err.alertStyle = .warning
                    err.runModal()
                }
            }
        }

        let response = progress.runModal()
        if response == .alertFirstButtonReturn { cancelled = true }
    }

    /// Streams the file in 64 KB chunks and feeds them into a `SHA256` hasher.
    /// Returns the lowercase hex digest, or an error.
    private func sha256(fileURL: URL, cancelled: () -> Bool) -> Result<String, Error> {
        guard let fh = FileHandle(forReadingAtPath: fileURL.path) else {
            return .failure(CocoaError(.fileReadNoPermission,
                userInfo: [NSLocalizedDescriptionKey: "Cannot open file for reading."]))
        }
        defer { fh.closeFile() }

        var hasher = SHA256()
        let chunkSize = 65_536   // 64 KB — keeps memory flat even for very large files
        while true {
            if cancelled() { return .failure(CancellationError()) }
            let chunk = fh.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return .success(hex)
    }

    private func showHashResult(hash: String, item: FileItem) {
        let alert = NSAlert()
        alert.messageText = "SHA-256 Hash"
        alert.informativeText = item.name
        alert.addButton(withTitle: "Copy to Clipboard")
        alert.addButton(withTitle: "Done")

        // Hash displayed in a monospaced, selectable text field
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 22))
        field.stringValue = hash
        field.isEditable = false
        field.isSelectable = true
        field.isBordered = true
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.cell?.truncatesLastVisibleLine = false
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hash, forType: .string)
        }
    }

    func openTerminal() {
        // Use "--" to ensure the path is never interpreted as a flag,
        // even if it somehow starts with a hyphen.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", "--", currentURL.path]
        try? task.run()
    }

    // MARK: - Breadcrumb

    private func breadcrumbName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        if url.path == fm.homeDirectoryForCurrentUser.path { return "Home" }
        if url.path == trashURL.path { return "Trash" }
        if url.path == "/Applications" { return "Applications" }
        return url.lastPathComponent
    }

    /// Canonical trash URL for the current user, resolved via FileManager API.
    var trashURL: URL {
        fm.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    var isInTrash: Bool { currentURL.path == trashURL.path }

    func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Empty Trash"
        alert.informativeText = "Are you sure you want to permanently delete the items in the Trash? This cannot be undone."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let contents = (try? fm.contentsOfDirectory(at: trashURL,
            includingPropertiesForKeys: nil, options: [])) ?? []
        var failures: [String] = []
        for url in contents {
            do { try fm.removeItem(at: url) }
            catch { failures.append(url.lastPathComponent) }
        }
        loadItems()
        if !failures.isEmpty {
            let err = NSAlert()
            err.messageText = "Could Not Delete All Items"
            err.informativeText = failures.joined(separator: "\n")
            err.alertStyle = .warning
            err.runModal()
        }
    }

    // MARK: - Sidebar

    private func buildSidebarSections() {
        var sections: [SidebarSection] = []

        // "Recents" sentinel — url is unused when isRecents = true
        let recentsItem = SidebarItem(name: "Recents",
                                      url: fm.homeDirectoryForCurrentUser,
                                      systemImage: "clock",
                                      isRecents: true)
        let quickItems: [(String, URL?, String)] = [
            ("Desktop",      fm.urls(for: .desktopDirectory,   in: .userDomainMask).first, "menubar.dock.rectangle"),
            ("Downloads",    fm.urls(for: .downloadsDirectory, in: .userDomainMask).first, "arrow.down.circle"),
            ("Documents",    fm.urls(for: .documentDirectory,  in: .userDomainMask).first, "doc"),
            ("Pictures",     fm.urls(for: .picturesDirectory,  in: .userDomainMask).first, "photo"),
            ("Music",        fm.urls(for: .musicDirectory,     in: .userDomainMask).first, "music.note"),
            ("Movies",       fm.urls(for: .moviesDirectory,    in: .userDomainMask).first, "film"),
            ("Applications", URL(fileURLWithPath: "/Applications"),                         "app.badge"),
        ]
        var quickSection = quickItems.compactMap { name, url, img -> SidebarItem? in
            guard let url = url else { return nil }
            return SidebarItem(name: name, url: url, systemImage: img)
        }
        quickSection.insert(recentsItem, at: 0)
        sections.append(SidebarSection(title: "Quick access", items: quickSection))

        sections.append(SidebarSection(title: "This Mac", items: [
            SidebarItem(name: "Home",         url: fm.homeDirectoryForCurrentUser,      systemImage: "house"),
            SidebarItem(name: "Macintosh HD", url: URL(fileURLWithPath: "/"),           systemImage: "internaldrive"),
            SidebarItem(name: "Trash",        url: trashURL,                            systemImage: "trash"),
        ]))

        let volumes = (try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsEjectableKey],
            options: .skipsHiddenFiles
        )) ?? []

        var localVols: [SidebarItem] = []
        var networkVols: [SidebarItem] = []
        for url in volumes {
            let res = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsEjectableKey])
            let isLocal     = res?.volumeIsLocal    ?? true
            let isRemovable = res?.volumeIsRemovable ?? false
            let isOptical   = res?.volumeIsEjectable ?? false   // true only for optical discs
            if isLocal {
                // Skip the startup-disk symlink (/Volumes/Macintosh HD → /)
                if url.resolvingSymlinksInPath().path == "/" { continue }
                let icon: String
                if isOptical {
                    icon = "opticaldisc"
                } else if isRemovable {
                    icon = "externaldrive"
                } else {
                    icon = "internaldrive"
                }
                localVols.append(SidebarItem(
                    name: url.lastPathComponent,
                    url: url,
                    systemImage: icon,
                    isEjectable: isRemovable || isOptical
                ))
            } else {
                networkVols.append(SidebarItem(
                    name: url.lastPathComponent,
                    url: url,
                    systemImage: "network",
                    isNetworkVolume: true,
                    isEjectable: true
                ))
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

// MARK: - Helpers

/// Reference wrapper — lets a closure capture a token that is assigned after the closure is created.
private final class Box<T> { var value: T? }

// MARK: - URL helpers

private extension URL {
    /// Returns the mount-point path for this URL's volume — same volume = move, different = copy.
    var volumeMountPoint: String {
        let result = "/"
        // Walk up the path until we reach a volume mount point
        var check = self.standardized
        while check.path != "/" {
            var isMount: ObjCBool = false
            if FileManager.default.fileExists(atPath: check.path, isDirectory: &isMount),
               (try? check.resourceValues(forKeys: [.isVolumeKey]).isVolume) == true {
                return check.path
            }
            check = check.deletingLastPathComponent()
        }
        return result
    }
}
