import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: FileManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView()
            Divider()

            HStack(spacing: 0) {
                SidebarView()

                Divider()

                VStack(spacing: 0) {
                    toolbarBar
                    Divider()
                    mainContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            StatusBarView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Toolbar strip

    var toolbarBar: some View {
        HStack(spacing: 4) {
            toolbarButton("folder.badge.plus", label: "New folder") { vm.newFolder() }

            Divider().frame(height: 20)

            toolbarButton("scissors",      label: "Cut",   enabled: !vm.selectedItemIDs.isEmpty) { vm.cutSelected() }
            toolbarButton("doc.on.doc",    label: "Copy",  enabled: !vm.selectedItemIDs.isEmpty) { vm.copySelected() }
            toolbarButton("doc.on.clipboard", label: "Paste", enabled: vm.canPaste)              { vm.paste() }

            Divider().frame(height: 20)

            toolbarButton("pencil", label: "Rename", enabled: vm.selectedItemIDs.count == 1) { vm.beginRename() }
            toolbarButton("trash",  label: "Delete",  enabled: !vm.selectedItemIDs.isEmpty)  { vm.deleteSelected() }

            Divider().frame(height: 20)

            toolbarButton("checkmark.square", label: "Select all") { vm.selectAll() }
            toolbarButton("square", label: "Deselect all", enabled: !vm.selectedItemIDs.isEmpty) { vm.clearSelection() }

            Divider().frame(height: 20)

            toolbarButton("terminal", label: "Terminal") { vm.openTerminal() }
            toolbarButton(vm.showHiddenFiles ? "eye.slash" : "eye",
                          label: vm.showHiddenFiles ? "Hide hidden" : "Show hidden") {
                vm.showHiddenFiles.toggle()
            }

            Divider().frame(height: 20)

            toolbarButton("network", label: "Connect") { vm.showConnectToServerDialog() }

            if vm.isInTrash {
                Divider().frame(height: 20)
                toolbarButton("trash.slash", label: "Empty Trash", enabled: !vm.items.isEmpty) { vm.emptyTrash() }
            }

            Spacer()

            Picker("", selection: $vm.viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.largeIcons).help("Large Icons")
                Image(systemName: "list.bullet").tag(ViewMode.details).help("Details")
            }
            .pickerStyle(.segmented)
            .frame(width: 60)
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    func toolbarButton(_ icon: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.system(size: 9))
            }
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(enabled ? .primary : .secondary)
        .disabled(!enabled)
        .help(label)
    }

    // MARK: - Main content

    @ViewBuilder
    var mainContent: some View {
        ZStack {
            Color(NSColor.textBackgroundColor)

            if vm.items.isEmpty && !vm.searchText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("No items match your search").foregroundColor(.secondary)
                }
            } else if vm.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: vm.isInTrash ? "trash" : "folder")
                        .font(.system(size: 48)).foregroundColor(.secondary)
                    Text(vm.isInTrash ? "Trash is empty" : "This folder is empty")
                        .foregroundColor(.secondary)
                }
            } else {
                switch vm.viewMode {
                case .largeIcons: FileGridView()
                case .details:    FileListView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { vm.clearSelection() }
    }
}
