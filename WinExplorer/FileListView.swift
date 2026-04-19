import SwiftUI

struct FileListView: View {
    @EnvironmentObject var vm: FileManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            columnHeaders
            Divider()
            fileRows
        }
    }

    // MARK: - Column Headers

    var columnHeaders: some View {
        HStack(spacing: 0) {
            headerCell("Name", field: .name, minWidth: 200)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 22)
            headerCell("Date modified", field: .dateModified, minWidth: 150)
                .frame(width: 165, alignment: .leading)
            Divider().frame(height: 22)
            headerCell("Type", field: .type, minWidth: 100)
                .frame(width: 130, alignment: .leading)
            Divider().frame(height: 22)
            headerCell("Size", field: .size, minWidth: 70)
                .frame(width: 85, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(height: 24)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    func headerCell(_ title: String, field: SortField, minWidth: CGFloat) -> some View {
        Button {
            vm.sortBy(field)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                if vm.sortField == field {
                    Image(systemName: vm.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - File Rows

    var fileRows: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.items) { item in
                    FileListRow(item: item)
                        .background(rowBg(item))
                        .onTapGesture { vm.selectedItemIDs = [item.id] }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    func rowBg(_ item: FileItem) -> Color {
        vm.selectedItemIDs.contains(item.id) ? Color.accentColor.opacity(0.2) : Color.clear
    }
}

struct FileListRow: View {
    @EnvironmentObject var vm: FileManagerViewModel
    let item: FileItem

    @State private var renameText: String = ""
    @State private var renameFocused: Bool = false

    var isRenaming: Bool { vm.renamingItemID == item.id }

    var body: some View {
        HStack(spacing: 0) {
            // Name column
            HStack(spacing: 5) {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)

                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        
                        .onSubmit { vm.commitRename(item: item, newName: renameText) }
                        .onExitCommand { vm.cancelRename() }
                } else {
                    Text(item.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.dateString)
                .font(.system(size: 12))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .frame(width: 165, alignment: .leading)
                .padding(.leading, 4)
                .lineLimit(1)

            Text(item.fileType)
                .font(.system(size: 12))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .frame(width: 130, alignment: .leading)
                .padding(.leading, 4)
                .lineLimit(1)

            Text(item.sizeString)
                .font(.system(size: 12))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .frame(width: 85, alignment: .trailing)
                .padding(.trailing, 8)
                .lineLimit(1)
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { vm.openItem(item) }
        .simultaneousGesture(TapGesture().onEnded { vm.selectedItemIDs = [item.id] })
        .contextMenu { contextMenu }
        .onChange(of: isRenaming) { renaming in
            if renaming {
                renameText = item.name
            }
        }
    }

    @ViewBuilder
    var contextMenu: some View {
        Button("Open") { vm.openItem(item) }
        Divider()
        Button("Cut")  { vm.selectedItemIDs = [item.id]; vm.cutSelected() }
        Button("Copy") { vm.selectedItemIDs = [item.id]; vm.copySelected() }
        Divider()
        Button("Rename") { vm.selectedItemIDs = [item.id]; vm.beginRename() }
        Button("Move to Trash") { vm.selectedItemIDs = [item.id]; vm.deleteSelected() }
        Divider()
        Button("Show in Finder") { vm.showInFinder(item) }
        if vm.isEjectableVolume(item) {
            Divider()
            Button("Eject") {
                vm.selectedItemIDs = [item.id]
                vm.disconnectVolume(item.url)
            }
        }
    }
}
