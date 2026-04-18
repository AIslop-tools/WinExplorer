# WinExplorer

A Windows Explorer–inspired file manager for macOS, built with SwiftUI and AppKit.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Dual view modes** — Large Icons grid and Details list, switchable via toolbar or ⌘1 / ⌘2
- **Breadcrumb navigation** — click any segment to jump up the hierarchy
- **Back / Forward / Up** navigation with full history stack
- **Sidebar** with quick access to Home, Desktop, Downloads, Documents, and Applications
- **Network drive support** — SMB, AFP, NFS, FTP/FTPS volumes auto-appear in the sidebar; eject button to disconnect
- **Connect to Server** — toolbar button and ⌘K to mount network shares by URL
- **File operations** — Cut, Copy, Paste, Rename (in-place), Move to Trash, New Folder
- **Search** — live filter in the toolbar
- **Show Hidden Files** toggle (⇧⌘.)
- **Open Terminal Here** — opens Terminal in the current folder
- **Show in Finder** — reveal selected item in Finder
- **Full macOS menu bar** — App, File, Edit, View, Go, and Window menus, fully keyboard-shortcut enabled
- **Select All / Deselect All** in toolbar and Edit menu
- **Context menu** on every file/folder

---

## Installation

### Option 1 — Pre-built DMG (recommended)

| Architecture | Download |
|---|---|
| Apple Silicon (M1/M2/M3/M4) | `WinExplorer-1.0-AppleSilicon.dmg` |
| Intel Mac | `WinExplorer-1.0-Intel.dmg` |

1. Download the DMG for your Mac.
2. Open the DMG and drag **WinExplorer.app** to **Applications**.
3. On first launch, right-click → Open to bypass Gatekeeper (app is ad-hoc signed, not notarized).

### Option 2 — Build from source

**Requirements:** macOS 13+, Xcode 15+ or Swift 5.9 toolchain

```bash
git clone https://github.com/AIslop-tools/WinExplorer.git
cd WinExplorer

# Apple Silicon
swiftc -target arm64-apple-macos13.0 -O \
    WinExplorer/main.swift \
    WinExplorer/FileManagerViewModel.swift \
    WinExplorer/ContentView.swift \
    WinExplorer/FileItem.swift \
    WinExplorer/AddressBarView.swift \
    WinExplorer/FileGridView.swift \
    WinExplorer/FileListView.swift \
    WinExplorer/SidebarView.swift \
    WinExplorer/StatusBarView.swift \
    WinExplorer/WinExplorerApp.swift \
    -framework SwiftUI -framework AppKit \
    -o WinExplorer

# Or open WinExplorer.xcodeproj in Xcode and press ⌘R
```

---

## Screenshots

> *Large Icons view — classic Windows Explorer feel on macOS*

> *Details view with sortable columns*

---

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New Folder | ⇧⌘N |
| Open | ⌘O |
| Move to Trash | ⌘⌫ |
| Cut | ⌘X |
| Copy | ⌘C |
| Paste | ⌘V |
| Select All | ⌘A |
| Large Icons | ⌘1 |
| Details | ⌘2 |
| Show Hidden Files | ⇧⌘. |
| Refresh | ⌘R |
| Back | ⌘[ |
| Forward | ⌘] |
| Enclosing Folder | ⌘↑ |
| Home | ⇧⌘H |
| Desktop | ⇧⌘D |
| Downloads | ⇧⌘L |
| Documents | ⇧⌘O |
| Applications | ⇧⌘A |
| Connect to Server | ⌘K |

---

## Architecture

```
WinExplorer/
├── main.swift                  # AppKit entry point, AppDelegate, menu bar
├── FileManagerViewModel.swift  # All business logic (ObservableObject)
├── ContentView.swift           # Root layout: sidebar + toolbar + content area
├── AddressBarView.swift        # Breadcrumb + search bar
├── FileGridView.swift          # Large Icons grid (LazyVGrid)
├── FileListView.swift          # Details list (List)
├── SidebarView.swift           # Sidebar with favorites and volumes
├── StatusBarView.swift         # Bottom status bar (item count, selection)
├── FileItem.swift              # File model struct
└── WinExplorerApp.swift        # Legacy stub (entry point is main.swift)
```

- **SwiftUI + AppKit hybrid** — SwiftUI views hosted in `NSHostingController` inside an `NSWindow`
- **ObservableObject / @Published** — reactive data flow, no manual refresh calls
- **NSWorkspace notifications** — live detection of volume mount/unmount events
- **Ad-hoc code signed** — works on any Mac without Developer ID

---

## Security Notes

- Rename blocks `/` and null bytes to prevent path traversal
- Paste validates that clipboard URLs are real files before acting
- Network URL scheme is allowlisted (`smb`, `afp`, `nfs`, `ftp`, `ftps`)
- Debug logging is gated behind `#if DEBUG` and writes only to the app's own temp directory
- Breadcrumb depth capped at 50 to prevent infinite loops
- Destination uniqueness limited to 1000 candidates before UUID fallback

---

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel x86_64

---

## License

MIT — see [LICENSE](LICENSE) for details.
