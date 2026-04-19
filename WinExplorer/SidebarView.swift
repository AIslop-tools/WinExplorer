import SwiftUI

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

    var isActive: Bool { vm.currentURL == item.url }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                vm.navigate(to: item.url)
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
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .foregroundColor(isActive ? .accentColor : .primary)
    }
}
