import AppKit
import SSHConfigKit
import SwiftUI

@main
struct HostKeeperApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @AppStorage("showMenuBar") private var showMenuBar = true

    init() {
        Self.migrateSettings()
        _ = Updater.shared  // starts Sparkle's scheduled update checks
    }

    /// Versions before 1.3 used the bundle ID local.hostkeeper.app; carry their settings over once.
    private static func migrateSettings() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromLocalID"), let old = UserDefaults(suiteName: "local.hostkeeper.app") else { return }
        for key in ["emptyFolders", "keyTags", "showMenuBar", "groupBy"] where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "migratedFromLocalID")
    }

    var body: some Scene {
        Window("HostKeeper", id: "main") {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About HostKeeper") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "HostKeeper",
                        .applicationVersion: AppVersion.version,
                        .version: AppVersion.build,
                        .credits: NSAttributedString(string: "A free editor for ~/.ssh/config and your SSH keys."),
                    ])
                    NSApp.activate()
                }
                CheckForUpdatesButton()
            }
            CommandGroup(replacing: .help) {
                HelpMenuItems()
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { ConfigStore.shared.save() }
                    .keyboardShortcut("s")
                Button("Revert to Saved") { ConfigStore.shared.load() }
            }
        }

        Window("HostKeeper Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 640)

        MenuBarExtra("HostKeeper", systemImage: "terminal", isInserted: $showMenuBar) {
            QuickConnectMenu()
        }

        Settings {
            SettingsView(showMenuBar: $showMenuBar)
        }
    }
}

private struct SettingsView: View {
    @Binding var showMenuBar: Bool
    @Bindable private var updater = Updater.shared

    var body: some View {
        Form {
            Toggle("Show quick-connect menu in the menu bar", isOn: $showMenuBar)
            Text("When it's on, closing the window keeps HostKeeper running in the menu bar.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
                .disabled(!updater.isAvailable)
            HStack {
                Text(updater.isAvailable
                     ? "HostKeeper checks once a day and asks before installing anything."
                     : "Updates are only available in the installed app, not in development builds.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                CheckForUpdatesButton()
            }
            Divider()
            LabeledContent("HostKeeper", value: AppVersion.display)
        }
        .padding()
        .frame(width: 460)
    }
}

private struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("HostKeeper Help") { open(.welcome) }
            .keyboardShortcut("?")
        Divider()
        ForEach(HelpTopic.allCases.dropFirst()) { topic in
            Button(topic.rawValue) { open(topic) }
        }
    }

    private func open(_ topic: HelpTopic) {
        HelpRouter.shared.topic = topic
        HelpRouter.shared.optionSearch = ""
        openWindow(id: "help")
    }
}

/// Menu bar list of hosts, grouped by folder; picking one opens it in Terminal.
private struct QuickConnectMenu: View {
    @Bindable private var store = ConfigStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let connectable = store.hosts.filter { $0.connectAlias != nil }
        ForEach(store.folders, id: \.self) { folder in
            let hosts = connectable.filter { $0.folder == folder }
            if !hosts.isEmpty {
                Menu(folder) { ForEach(hosts) { button($0) } }
            }
        }
        ForEach(connectable.filter { $0.folder.isEmpty }) { button($0) }
        if connectable.isEmpty { Text("No hosts yet") }
        Divider()
        Button("HostKeeper Help") {
            HelpRouter.shared.topic = .welcome
            openWindow(id: "help")
            NSApp.activate()
        }
        CheckForUpdatesButton()
        Button("Open HostKeeper…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Quit HostKeeper") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func button(_ host: HostBlock) -> some View {
        Button(host.pattern) { if let alias = host.connectAlias { HostActions.connect(alias) } }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable from Xcode/SwiftPM rather than a bundled .app.
        NSApp.setActivationPolicy(.regular)
        if Bundle.main.bundleURL.pathExtension != "app" { Self.useIconFromSourceTree() }
        NSApp.activate()
    }

    /// A bare executable (Xcode ⌘R, `swift run`) has no bundle icon, so load it from the repo for the Dock.
    @MainActor private static func useIconFromSourceTree(sourceFile: String = #filePath) {
        let icon = URL(filePath: sourceFile)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/AppIcon.icns")
        if let image = NSImage(contentsOf: icon) { NSApp.applicationIconImage = image }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true)
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = ConfigStore.shared
        guard store.isDirty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Save changes to your SSH config?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return store.save() ? .terminateNow : .terminateCancel
        case .alertSecondButtonReturn: return .terminateCancel
        default: return .terminateNow
        }
    }
}
