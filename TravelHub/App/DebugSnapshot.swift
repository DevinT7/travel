#if DEBUG && os(macOS)
import AppKit
import SwiftUI

/// Debug-only: when launched with `-Snapshot YES`, renders the main window for each tab to PNGs in
/// the app's temporary folder, so the Mac layout can be checked without screen-recording access.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(model: AppModel) async {
        guard UserDefaults.standard.bool(forKey: "Snapshot") else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let only = UserDefaults.standard.string(forKey: "SnapshotTabs")?.split(separator: ",").map(String.init)
        for tab in [AppTab.trip, .discover, .plan, .trips] where only?.contains("\(tab)") ?? true {
            model.selectedTab = tab
            try? await Task.sleep(for: .seconds(6))
            capture(to: folder.appendingPathComponent("\(tab).png"))
        }
        print("SNAPSHOTS_DONE \(folder.path)")
        if UserDefaults.standard.bool(forKey: "SnapshotQuit") { NSApp.terminate(nil) }
    }

    private static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
