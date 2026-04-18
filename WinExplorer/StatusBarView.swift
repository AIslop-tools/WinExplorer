import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var vm: FileManagerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text(vm.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .padding(.leading, 8)
            Spacer()
            if !vm.searchText.isEmpty {
                Text("Searching for \"\(vm.searchText)\"")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .padding(.trailing, 8)
            }
        }
        .frame(height: 22)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
