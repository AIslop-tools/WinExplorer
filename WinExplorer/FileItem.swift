import Foundation
import AppKit

class FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int64?
    let modificationDate: Date?
    let fileType: String
    let icon: NSImage

    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = attrs?[.size] as? Int64
        self.modificationDate = attrs?[.modificationDate] as? Date

        if isDir.boolValue {
            self.fileType = "File folder"
        } else {
            let ext = url.pathExtension.uppercased()
            self.fileType = ext.isEmpty ? "File" : "\(ext) File"
        }
        // Use a shared icon cache to avoid redundant NSWorkspace lookups on every refresh
        if let cached = FileItem.iconCache.object(forKey: url as NSURL) {
            self.icon = cached
        } else {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            FileItem.iconCache.setObject(img, forKey: url as NSURL)
            self.icon = img
        }
    }

    var sizeString: String {
        guard !isDirectory, let size = fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var dateString: String {
        guard let date = modificationDate else { return "" }
        return FileItem.dateFormatter.string(from: date)
    }

    /// Shared icon cache — keyed by NSURL, auto-evicted under memory pressure.
    private static let iconCache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 2000
        return c
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
