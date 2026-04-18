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
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    var sizeString: String {
        guard !isDirectory, let size = fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var dateString: String {
        guard let date = modificationDate else { return "" }
        return FileItem.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
