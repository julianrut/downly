import AppKit
import DownlyCore
import SwiftUI

@main
struct DownlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var model = AppModel()

    var body: some Scene {
        Window("Downly", id: "main") {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .onAppear {
                    appDelegate.model = model
                    if SnapshotRunner.directory == nil {
                        model.start()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download") {
                    model.clear()
                }
                .keyboardShortcut("n")
                Button("Paste Link") {
                    model.pasteFromClipboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Open Downloads Folder") {
                    NSWorkspace.shared.open(Preferences.downloadFolder)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.accent)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = SnapshotRunner.directory {
            Task { @MainActor in
                await SnapshotRunner.run(into: directory, delegate: self)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let candidates = sender.windows.filter { $0.canBecomeMain }
            let main = candidates.first { $0.identifier?.rawValue.hasPrefix("main") == true } ?? candidates.first { $0.title == "Downly" }
            if let main {
                main.makeKeyAndOrderFront(nil)
                return false
            }
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.downloads.activeCount > 0, SnapshotRunner.directory == nil else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Downloads are still running"
        alert.informativeText = "Quitting now cancels \(model.downloads.activeCount == 1 ? "1 download" : "\(model.downloads.activeCount) downloads")."
        alert.addButton(withTitle: "Keep Downloading")
        alert.addButton(withTitle: "Quit Anyway")
        alert.alertStyle = .warning
        if alert.runModal() == .alertSecondButtonReturn {
            model.downloads.cancelAll()
            return .terminateNow
        }
        return .terminateCancel
    }
}
