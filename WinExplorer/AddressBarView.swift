import SwiftUI

struct AddressBarView: View {
    @EnvironmentObject var vm: FileManagerViewModel
    @State private var isEditing = false
    @State private var editText = ""
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 6) {
            // Nav buttons
            HStack(spacing: 0) {
                navButton("chevron.left",    help: "Back",    enabled: vm.canGoBack)    { vm.goBack() }
                navButton("chevron.right",   help: "Forward", enabled: vm.canGoForward) { vm.goForward() }
                navButton("arrow.up",        help: "Up",      enabled: vm.canGoUp)      { vm.goUp() }
                navButton("arrow.clockwise", help: "Refresh", enabled: true)            { vm.loadItems() }
            }

            // Address bar
            ZStack(alignment: .leading) {
                if isEditing {
                    TextField("Path", text: $editText, onCommit: commitPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                } else {
                    HStack(spacing: 0) {
                        ForEach(vm.breadcrumbs) { crumb in
                            let isLast = crumb.id == vm.breadcrumbs.last?.id
                            if crumb.id != vm.breadcrumbs.first?.id {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 2)
                            }
                            Button(crumb.name) { vm.navigate(to: crumb.url) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundColor(isLast ? .primary : Color(NSColor.secondaryLabelColor))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.35), lineWidth: 1))
            .onTapGesture {
                editText = vm.currentURL.path
                isEditing = true
            }

            // Search — local @State avoids vm.searchText didSet cascade during layout
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 150)
                    .onChange(of: searchText) { vm.searchText = $0 }
                if !searchText.isEmpty {
                    Button { searchText = ""; vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    func navButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(enabled ? .primary : .secondary)
        .disabled(!enabled)
        .help(help)
    }

    func commitPath() {
        isEditing = false
        let path = (editText as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            vm.navigate(to: url)
        } else {
            // Restore the previous path and tell the user what went wrong
            editText = vm.currentURL.path
            let alert = NSAlert()
            alert.messageText = "Folder Not Found"
            alert.informativeText = "\"\(path)\" does not exist or is not a folder."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
