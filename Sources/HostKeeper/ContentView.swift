import AppKit
import SSHConfigKit
import SwiftUI

enum GroupBy: String, CaseIterable {
    case folders = "Folders", tags = "Tags", none = "All"
}

enum SidebarItem: Hashable {
    case block(UUID)
    case key(String)
    case backups
}

struct ContentView: View {
    @Bindable private var store = ConfigStore.shared
    @Bindable private var keyStore = KeyStore.shared
    @State private var selection: SidebarItem?
    @State private var search = ""
    @State private var collapsed: Set<String> = []
    @State private var showingFile = false
    @State private var showingGenerate = false
    @State private var confirmDelete = false
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""
    @State private var renamingTag: String?
    @State private var tagName = ""
    @AppStorage("groupBy") private var groupBy: GroupBy = .folders

    private struct FolderPrompt: Identifiable {
        var id: String { renaming ?? "+" }
        var renaming: String?
    }

    private var selectedBlockIndex: Int? {
        guard case .block(let id) = selection else { return nil }
        return store.config.blocks.firstIndex { $0.id == id }
    }

    private var selectedHostID: UUID? {
        guard let i = selectedBlockIndex, store.config.blocks[i].kind != .global else { return nil }
        return store.config.blocks[i].id
    }

    private var query: SearchQuery { SearchQuery(search) }

    private var matchingHosts: [HostBlock] {
        let query = self.query
        guard !query.isEmpty else { return store.hosts }
        return store.hosts.filter { host in
            query.matches(
                fields: [host.pattern, host.value("HostName"), host.value("User"), host.note, host.folder],
                tags: host.tags)
        }
    }

    private func hosts(in folder: String) -> [HostBlock] {
        matchingHosts.filter { $0.folder == folder }
    }

    private var matchingKeys: [SSHKey] {
        let query = self.query
        guard !query.isEmpty else { return keyStore.keys }
        return keyStore.keys.filter { key in
            query.matches(fields: [key.name, key.comment, key.type], tags: keyStore.tags(for: key))
        }
    }

    /// Adds or removes `#tag` in the filter box.
    private func toggleTagFilter(_ tag: String) {
        var words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        if let i = words.firstIndex(where: { $0.caseInsensitiveCompare("#" + tag) == .orderedSame }) {
            words.remove(at: i)
        } else {
            words.append("#" + tag)
        }
        search = words.joined(separator: " ")
    }

    private func isFiltering(_ tag: String) -> Bool {
        query.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .searchable(text: $search, placement: .sidebar, prompt: "Filter, or #tag")
                .navigationSplitViewColumnWidth(min: 230, ideal: 270)
        } detail: {
            detail
        }
        .navigationTitle("HostKeeper")
        .navigationSubtitle(Shell.abbreviate(store.url.path) + (store.isDirty ? " — Edited" : ""))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if Paths.isPractice {
                Label("Practice mode: editing \(Shell.abbreviate(store.url.path)). Your real ~/.ssh is not touched.",
                      systemImage: "hammer")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(.yellow.opacity(0.25))
            }
        }
        .toolbar { toolbar }
        .confirmationDialog("Delete this host?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let id = selectedHostID { store.delete(id); selection = nil }
            }
        } message: {
            Text("It's removed when you save. Every save keeps a backup you can restore from Backups.")
        }
        .alert(folderPrompt?.renaming == nil ? "New Folder" : "Rename Folder", isPresented: Binding(
            get: { folderPrompt != nil },
            set: { if !$0 { folderPrompt = nil } }
        )) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button(folderPrompt?.renaming == nil ? "Create" : "Rename") {
                if let old = folderPrompt?.renaming {
                    store.renameFolder(old, to: folderName)
                } else {
                    store.addFolder(folderName)
                }
            }
        }
        .alert("Rename Tag", isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField("Tag name", text: $tagName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let old = renamingTag { store.renameTag(old, to: tagName) }
            }
        } message: {
            Text("Renames the tag on every host and key that has it.")
        }
        .sheet(isPresented: $showingFile) {
            FilePreview(title: "This is what will be written to ~/.ssh/config", text: store.config.render())
        }
        .sheet(isPresented: $showingGenerate) {
            GenerateKeySheet { path in selection = .key(path) }
        }
        .alert("Problem", isPresented: Binding(
            get: { store.errorMessage != nil || keyStore.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil; keyStore.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? keyStore.errorMessage ?? "")
        }
        .onAppear { selection = selection ?? store.hosts.first.map { .block($0.id) } }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            if let global = store.config.blocks.first, global.kind == .global, !global.options.isEmpty, search.isEmpty {
                Label("Global settings", systemImage: "globe").tag(SidebarItem.block(global.id))
            }

            switch groupBy {
            case .folders: folderSections
            case .tags: tagSections
            case .none:
                Section("All Hosts (\(matchingHosts.count))") {
                    ForEach(matchingHosts) { hostRow($0) }
                }
            }

            Section(isExpanded: expansion("\u{0}keys")) {
                ForEach(matchingKeys) { key in
                    KeyRow(key: key, tags: keyStore.tags(for: key)).tag(SidebarItem.key(key.path))
                }
            } header: {
                Text("Keys (\(matchingKeys.count))")
            }

            Section("Safety") {
                Label("Backups", systemImage: "clock.arrow.circlepath").tag(SidebarItem.backups)
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Group by", selection: $groupBy) {
                ForEach(GroupBy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .help("Group hosts by folder, by tag, or show them all in one list")
        }
        .safeAreaInset(edge: .bottom) {
            Text(AppVersion.display).font(.caption2).foregroundStyle(.tertiary).padding(6)
        }
    }

    @ViewBuilder private var folderSections: some View {
        ForEach(store.folders, id: \.self) { folder in
            Section(isExpanded: expansion(folder)) {
                ForEach(hosts(in: folder)) { hostRow($0) }
            } header: {
                Label(folder, systemImage: "folder")
                    .dropDestination(for: String.self) { ids, _ in drop(ids, into: folder) }
                    .contextMenu {
                        Button("New Host in \(folder)") { selection = .block(store.addHost(inFolder: folder)) }
                        Button("Rename…") { folderName = folder; folderPrompt = FolderPrompt(renaming: folder) }
                        Button("Delete Folder (keeps hosts)", role: .destructive) { store.deleteFolder(folder) }
                    }
            }
        }

        let unfiled = hosts(in: "")
        if !unfiled.isEmpty || store.folders.isEmpty {
            Section {
                ForEach(unfiled) { hostRow($0) }
            } header: {
                Text(store.folders.isEmpty ? "Hosts" : "Unfiled")
                    .dropDestination(for: String.self) { ids, _ in drop(ids, into: "") }
            }
        }
    }

    /// A host appears once under each of its tags.
    @ViewBuilder private var tagSections: some View {
        ForEach(store.hostTags, id: \.self) { tag in
            let tagged = matchingHosts.filter { $0.hasTag(tag) }
            if !tagged.isEmpty {
                Section(isExpanded: expansion("#" + tag)) {
                    ForEach(tagged) { hostRow($0) }
                } header: {
                    Label {
                        Text("\(tag) (\(tagged.count))")
                    } icon: {
                        Image(systemName: "tag.fill").foregroundStyle(Tags.color(tag))
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        let uuids = ids.compactMap(UUID.init(uuidString:))
                        uuids.forEach { store.addTag(tag, to: $0) }
                        return !uuids.isEmpty
                    }
                    .contextMenu { tagMenu(tag) }
                }
            }
        }
        let untagged = matchingHosts.filter(\.tags.isEmpty)
        if !untagged.isEmpty {
            Section("Untagged (\(untagged.count))") {
                ForEach(untagged) { hostRow($0) }
            }
        }
    }

    @ViewBuilder private func tagMenu(_ tag: String) -> some View {
        Button(isFiltering(tag) ? "Stop Filtering by #\(tag)" : "Show Only #\(tag)") { toggleTagFilter(tag) }
        Button("Rename Tag…") { tagName = tag; renamingTag = tag }
        Button("Remove Tag from Everything", role: .destructive) { store.renameTag(tag, to: "") }
    }

    private func hostRow(_ host: HostBlock) -> some View {
        HostRow(host: host)
            .tag(SidebarItem.block(host.id))
            .draggable(host.id.uuidString)
            .contextMenu {
                if !host.tags.isEmpty {
                    Menu("Tags") {
                        ForEach(host.tags, id: \.self) { tag in
                            Menu(tag) { tagMenu(tag) }
                        }
                    }
                }
                Menu("Move to Folder") {
                    Button("Unfiled") { store.move(host.id, toFolder: "") }
                    Divider()
                    ForEach(store.folders, id: \.self) { folder in
                        Button(folder) { store.move(host.id, toFolder: folder) }
                    }
                }
                if let alias = host.connectAlias {
                    Button("Connect in Terminal") { HostActions.connect(alias) }
                    Button("Copy ssh \(alias)") { Shell.copy("ssh \(alias)") }
                }
                Button("Duplicate") { if let copy = store.duplicate(host.id) { selection = .block(copy) } }
                Button("Delete", role: .destructive) { selection = .block(host.id); confirmDelete = true }
            }
    }

    private func expansion(_ folder: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(folder) || !search.isEmpty },
            set: { if $0 { collapsed.remove(folder) } else { collapsed.insert(folder) } }
        )
    }

    private func drop(_ ids: [String], into folder: String) -> Bool {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        uuids.forEach { store.move($0, toFolder: folder) }
        return !uuids.isEmpty
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .block:
            if let i = selectedBlockIndex {
                HostDetailView(block: $store.config.blocks[i]).id(store.config.blocks[i].id)
            } else {
                placeholder
            }
        case .key(let path):
            if let key = keyStore.keys.first(where: { $0.path == path }) {
                KeyDetailView(key: key)
            } else {
                placeholder
            }
        case .backups:
            BackupsView()
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Nothing Selected",
            systemImage: "server.rack",
            description: Text("Pick a host or key on the left, or add one with +.")
        )
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu("Add", systemImage: "plus") {
                Button("New Host") { selection = .block(store.addHost(inFolder: currentFolder)) }
                Button("New Folder…") { folderName = ""; folderPrompt = FolderPrompt() }
                Divider()
                Button("Generate SSH Key…") { showingGenerate = true }
                Button("Import SSH Key…", action: importKey)
            } primaryAction: {
                selection = .block(store.addHost(inFolder: currentFolder))
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                if let id = selectedHostID, let copy = store.duplicate(id) { selection = .block(copy) }
            }
            .disabled(selectedHostID == nil)
            Button("Delete", systemImage: "trash") { confirmDelete = true }
                .disabled(selectedHostID == nil)
            Menu("Filter by Tag", systemImage: query.tags.isEmpty ? "tag" : "tag.fill") {
                let all = Tags.all
                if all.isEmpty { Text("No tags yet. Add them on a host or key page.") }
                ForEach(all, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(get: { isFiltering(tag) }, set: { _ in toggleTagFilter(tag) }))
                }
                if !query.tags.isEmpty {
                    Divider()
                    Button("Clear Tag Filters") {
                        search = query.words.joined(separator: " ")
                    }
                }
            }
            .help("Show only hosts and keys with these tags")
            Button("View File", systemImage: "doc.plaintext") { showingFile = true }
            Button("Save", systemImage: "square.and.arrow.down") { store.save() }
                .disabled(!store.isDirty)
            OpenHelpButton(topic: helpTopic)
        }
    }

    private var helpTopic: HelpTopic {
        switch selection {
        case .key: .keys
        case .backups: .saving
        case .block: .hosts
        case nil: .welcome
        }
    }

    /// New hosts land in the folder of the currently selected host.
    private var currentFolder: String {
        selectedBlockIndex.map { store.config.blocks[$0].folder } ?? ""
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose a private key to copy into ~/.ssh"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        keyStore.importKey(from: url)
    }
}

private struct HostRow: View {
    let host: HostBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if host.kind == .match {
                    Text("Match").font(.caption2).foregroundStyle(.secondary)
                }
                Text(host.pattern.isEmpty ? "(empty)" : host.pattern).lineLimit(1)
            }
            if !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            TagLine(tags: host.tags)
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let user = host.value("User")
        let name = host.value("HostName")
        let port = host.value("Port")
        var s = user.isEmpty ? name : (name.isEmpty ? user : "\(user)@\(name)")
        if !port.isEmpty && port != "22" { s += ":\(port)" }
        return s
    }
}

private struct KeyRow: View {
    let key: SSHKey
    let tags: [String]

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name).lineLimit(1)
                Text([key.type, key.hasPrivate ? nil : "public only"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                TagLine(tags: tags)
            }
        } icon: {
            Image(systemName: key.permissionsTooOpen ? "exclamationmark.triangle" : "key")
                .foregroundStyle(key.permissionsTooOpen ? .orange : .secondary)
        }
    }
}

struct FilePreview: View {
    let title: String
    let text: String
    var action: (label: String, run: () -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 6))
            HStack {
                Button("Copy") { Shell.copy(text) }
                Spacer()
                if let action {
                    Button(action.label) { action.run(); dismiss() }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 520)
    }
}
