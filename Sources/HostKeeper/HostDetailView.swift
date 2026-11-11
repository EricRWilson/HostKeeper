import AppKit
import SSHConfigKit
import SwiftUI

enum HostActions {
    /// Opens `ssh alias` in Terminal. Unsaved edits are used via a temporary copy of the config.
    @MainActor static func connect(_ alias: String) {
        let store = ConfigStore.shared
        if store.isDirty, let tmp = store.writeTempConfig() {
            Shell.runInTerminal("/usr/bin/ssh -F \(Shell.quote(tmp.path)) \(Shell.quote(alias))")
        } else {
            Shell.runInTerminal("/usr/bin/ssh \(Paths.sshConfigFlag)\(Shell.quote(alias))")
        }
    }
}

struct HostDetailView: View {
    @Binding var block: HostBlock
    @Bindable private var store = ConfigStore.shared
    @Bindable private var keyStore = KeyStore.shared
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, running, passed, failed(String)
    }

    /// Options that get a dedicated control; everything else shows under "Other options".
    private static let managed: Set<String> = [
        "hostname", "user", "port", "identityfile", "proxyjump",
        "forwardagent", "identitiesonly", "addkeystoagent", "serveraliveinterval",
    ]

    var body: some View {
        Form {
            if block.kind != .global {
                Section {
                    TextField(block.kind == .host ? "Host" : "Match", text: $block.pattern, prompt: Text("alias another-alias"))
                        .font(.title3)
                    Picker("Folder", selection: Binding(
                        get: { block.folder },
                        set: { store.move(block.id, toFolder: $0) }
                    )) {
                        Text("Unfiled").tag("")
                        Divider()
                        ForEach(store.folders, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Notes", text: $block.note, prompt: Text("What is this box? (saved as a comment)"))
                    TagEditor(tags: $block.tags)
                } footer: {
                    Text(block.kind == .host
                         ? "The name(s) you type after ssh. Separate several with spaces; * and ? are wildcards."
                         : "Match criteria, e.g. host *.corp user admin")
                }
            }

            if let alias = block.connectAlias {
                connectSection(alias)
            }

            Section {
                field("HostName", prompt: "example.com or 192.168.1.10")
                field("User", prompt: "your-username")
                field("Port", prompt: "22")
                HStack {
                    field("IdentityFile", prompt: "~/.ssh/id_ed25519")
                    Menu("Key") {
                        ForEach(keyStore.keys.filter(\.hasPrivate)) { key in
                            Button(key.name) { block.set("IdentityFile", Shell.abbreviate(key.path)) }
                        }
                        Divider()
                        Button("Choose File…", action: chooseKey)
                        Button("None") { block.set("IdentityFile", "") }
                    }
                    .fixedSize()
                }
                field("ProxyJump", prompt: "bastion (optional)")
            } header: {
                header("Connection", topic: .hosts)
            }

            Section {
                yesNo("ForwardAgent", label: "Forward SSH agent")
                yesNo("IdentitiesOnly", label: "Only use the identity file above")
                yesNo("AddKeysToAgent", label: "Add keys to agent")
                field("ServerAliveInterval", prompt: "seconds, e.g. 60")
            } header: {
                header("Behavior", topic: .hosts)
            }

            Section {
                ForEach($block.lines) { $line in
                    if line.isOption && !Self.managed.contains(line.key.lowercased()) {
                        HStack {
                            TextField("Key", text: $line.key).frame(maxWidth: 200)
                                .help(OptionReference.info(for: line.key)?.summary ?? "Not in HostKeeper's reference. See man ssh_config.")
                            TextField("Value", text: $line.value)
                            Button("Remove", systemImage: "minus.circle") {
                                block.lines.removeAll { $0.id == line.id }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Menu("Add Option") {
                    ForEach(["LocalForward", "RemoteForward", "DynamicForward", "RequestTTY", "RemoteCommand",
                             "SetEnv", "Compression", "StrictHostKeyChecking", "UseKeychain"], id: \.self) { key in
                        Button(key) { addOption(key) }
                            .help(OptionReference.info(for: key)?.summary ?? "")
                    }
                    Divider()
                    Button("Custom…") { addOption("NewOption") }
                }
                .fixedSize()
            } header: {
                header("Other options", topic: .options)
            } footer: {
                Text("Any ssh_config keyword works here. Hover a name to see what it does. Comments in your file are kept as-is.")
            }
        }
        .formStyle(.grouped)
    }

    private func connectSection(_ alias: String) -> some View {
        Section {
            HStack {
                Text("ssh \(alias)").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy") { Shell.copy("ssh \(alias)") }
                Button("Open in Terminal") { HostActions.connect(alias) }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Button("Test Connection") { test(alias) }
                    .disabled(testState == .running)
                Button("Install Public Key on Server…") { installKey(alias) }
                    .disabled(publicKeyPath == nil || store.isDirty)
                    .help(store.isDirty ? "Save first so ssh-copy-id sees this host's settings"
                          : publicKeyPath == nil ? "Set an IdentityFile that has a .pub next to it"
                          : "Runs ssh-copy-id so you can log in without a password")
                Spacer()
                switch testState {
                case .idle: EmptyView()
                case .running: ProgressView().controlSize(.small)
                case .passed: Label("Logged in successfully", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let why): Label(why, systemImage: "xmark.circle.fill").foregroundStyle(.red).lineLimit(2)
                }
            }
        } header: {
            header("Connect", topic: .connecting)
        } footer: {
            Text("Test tries to log in with your keys only (no password prompt) and runs nothing on the server.")
        }
    }

    private var publicKeyPath: String? {
        let identity = block.value("IdentityFile")
        guard !identity.isEmpty else { return nil }
        let pub = Shell.expandTilde(identity) + ".pub"
        return FileManager.default.fileExists(atPath: pub) ? pub : nil
    }

    private func test(_ alias: String) {
        guard let tmp = store.writeTempConfig() else { return }
        testState = .running
        Task {
            let result = await Task.detached {
                Shell.run("/usr/bin/ssh", ["-F", tmp.path, "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                                           "-o", "RequestTTY=no", "-o", "RemoteCommand=none", alias, "true"])
            }.value
            try? FileManager.default.removeItem(at: tmp)
            if result.status == 0 {
                testState = .passed
            } else {
                let last = result.error.split(separator: "\n").last.map(String.init) ?? "Failed"
                testState = .failed(last.contains("Permission denied")
                                    ? "Server reachable, but key login was refused (or needs a passphrase)"
                                    : last)
            }
        }
    }

    private func installKey(_ alias: String) {
        guard let pub = publicKeyPath else { return }
        Shell.runInTerminal("/usr/bin/ssh-copy-id \(Paths.sshConfigFlag)-i \(Shell.quote(pub)) \(Shell.quote(alias))")
    }

    private func addOption(_ key: String) {
        let insertAt = (block.lines.lastIndex(where: \.isOption) ?? -1) + 1
        block.lines.insert(ConfigLine(key: key, value: ""), at: insertAt)
    }

    private func header(_ title: String, topic: HelpTopic) -> some View {
        HStack {
            Text(title)
            Spacer()
            OpenHelpButton(topic: topic)
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { block.value(key) }, set: { block.set(key, $0) })
    }

    private func field(_ key: String, prompt: String) -> some View {
        TextField(key, text: binding(key), prompt: Text(prompt))
            .help(OptionReference.info(for: key)?.summary ?? "")
    }

    private func yesNo(_ key: String, label: String) -> some View {
        Picker(label, selection: binding(key)) {
            Text("Default").tag("")
            Text("Yes").tag("yes")
            Text("No").tag("no")
            let current = block.value(key)
            if !["", "yes", "no"].contains(current) { Text(current).tag(current) }
        }
        .help("\(key): \(OptionReference.info(for: key)?.summary ?? "")")
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = KeyStore.shared.directory
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose the private key (not the .pub file)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        block.set("IdentityFile", Shell.abbreviate(url.path))
    }
}
