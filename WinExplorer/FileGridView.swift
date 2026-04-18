import SwiftUI

struct FileGridView: View {
    @EnvironmentObject var vm: FileManagerViewModel

    let columns = [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 4)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(vm.items) { item in
                    FileGridCell(item: item)
                }
            }
            .padding(8)
        }
        .background(Color(NSColor.textBackgroundColor))
        .onTapGesture { vm.clearSelection() }
    }
}

struct FileGridCell: View {
    @EnvironmentObject var vm: FileManagerViewModel
    let item: FileItem

    @State private var isHovered = false
    @State private var renameText = ""
    @State private var renameFocused: Bool = false

    var isSelected: Bool { vm.selectedItemIDs.contains(item.id) }
    var isRenaming: Bool { vm.renamingItemID == item.id }

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)

            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    
                    .onSubmit { vm.commitRename(item: item, newName: renameText) }
                    .onExitCommand { vm.cancelRename() }
                    .frame(width: 82)
            } else {
                Text(item.name)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .frame(width: 82)
            }
        }
        .frame(width: 90, height: 82)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : (isHovered ? Color.gray.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .onHover { isHovered = $0 }
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
    }
}
