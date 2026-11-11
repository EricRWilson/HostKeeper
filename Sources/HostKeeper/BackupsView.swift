import AppKit
import SSHConfigKit
import SwiftUI

struct BackupsView: View {
    @Bindable private var store = ConfigStore.shared
    @State private var backups: [URL] = []
    @State private var previewing: Preview?

    private struct Preview: Identifiable {
        let url: URL
        let text: String
        var id: URL { url }
    }

    var body: some View {
        Form {
            Section {
                if backups.isEmpty {
                    Text("No backups yet. One is made automatically every time you save.")
                        .foregroundStyle(.secondary)
                }
                ForEach(backups, id: \.self) { url in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(date(url))
                            Text(summary(url)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Preview") {
                            previewing = Preview(url: url, text: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
                        }
                        Button("Restore") { store.restore(url) }
                            .help("Loads this version into the editor. Nothing changes on disk until you save.")
                    }
                }
            } header: {
                HStack {
                    Text("Saved versions of ~/.ssh/config")
                    Spacer()
                    OpenHelpButton(topic: .saving)
                }
            } footer: {
                Text("The 30 most recent are kept in ~/.ssh/hostkeeper-backups. Restoring loads the version as unsaved changes, so you can review it first.")
            }
            Section {
                Button("Show Backups in Finder", systemImage: "folder") {
                    NSWorkspace.shared.open(store.backupDirectory)
                }
                .disabled(backups.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onAppear { backups = store.backups() }
        .onChange(of: store.savedText) { backups = store.backups() }
        .sheet(item: $previewing) { preview in
            FilePreview(title: date(preview.url), text: preview.text,
                        action: ("Restore This Version", { store.restore(preview.url) }))
        }
    }

    private func date(_ url: URL) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        // The backup's own mtime is when it was copied, i.e. when the newer version was saved over it.
        return (modified ?? .now).formatted(date: .abbreviated, time: .standard)
    }

    private func summary(_ url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let hosts = SSHConfig.parse(text).blocks.filter { $0.kind != .global }.count
        return "\(hosts) hosts · \(text.utf8.count.formatted(.byteCount(style: .file)))"
    }
}
