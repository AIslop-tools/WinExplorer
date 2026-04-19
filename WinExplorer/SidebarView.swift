import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var vm: FileManagerViewModel

    var body: some View {
        List {
            ForEach(vm.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        SidebarRow(item: item)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(minWidth: 170, idealWidth: 200, maxWidth: 240)
    }
}

struct SidebarRow: View {
    @EnvironmentObject var vm: FileManagerViewModel
    let item: SidebarItem

    @State private var isDropTargeted = false

    var isActive: Bool {
        item.isRecents ? vm.isShowingRecents : (!vm.isShowingRecents && vm.currentURL == item.url)
    }
    /// Sidebar items that are real folders accept drops (not Recents, not eject-only volumes)
    var acceptsDrop: Bool { !item.isRecents }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if item.isRecents { vm.showRecents() } else { vm.navigate(to: item.url) }
            } label: {
                Label(item.name, systemImage: item.systemImage)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.isEjectable {
                Button {
                    vm.disconnectVolume(item.url)
                } label: {
                    Image(systemName: "eject")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(item.isNetworkVolume ? "Disconnect" : "Eject")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isDropTargeted    ? Color.accentColor.opacity(0.25)
                      : isActive        ? Color.accentColor.opacity(0.18)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .foregroundColor(isActive ? .accentColor : .primary)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            defer { isDropTargeted = false }   // always clear highlight, even on rejection
            guard acceptsDrop else { return false }
            return vm.performDrop(providers: providers, into: item.url)
        }
    }
}
