import AppKit
import SSHConfigKit
import SwiftUI

struct KeyDetailView: View {
    let key: SSHKey
    @Bindable private var store = ConfigStore.shared
    @State private var confirmTrash = false

    private var usedBy: [HostBlock] {
        store.hosts.filter { Shell.expandTilde($0.value("IdentityFile")) == key.path }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: key.name)
                LabeledContent("Location", value: Shell.abbreviate(key.path))
                if !key.type.isEmpty { LabeledContent("Type", value: "\(key.type) · \(key.bits) bits") }
                if !key.comment.isEmpty { LabeledContent("Comment", value: key.comment) }
                TagEditor(tags: Binding(
                    get: { KeyStore.shared.tags(for: key) },
                    set: { KeyStore.shared.setTags($0, for: key) }
                ))
                if !key.fingerprint.isEmpty {
                    LabeledContent("Fingerprint") {
                        Text(key.fingerprint).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }

            if key.permissionsTooOpen {
                Section {
                    HStack {
                        Label("Other users can read this private key, so ssh will refuse to use it.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Fix Permissions") { KeyStore.shared.fixPermissions(key) }
                    }
                }
            }

            Section {
                if key.publicKey.isEmpty {
                    Text("No .pub file found next to this key.").foregroundStyle(.secondary)
                } else {
                    Text(key.publicKey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(4)
                    Button("Copy Public Key", systemImage: "doc.on.doc") { Shell.copy(key.publicKey) }
                }
            } header: {
                HStack {
                    Text("Public key")
                    Spacer()
                    OpenHelpButton(topic: .keys)
                }
            } footer: {
                Text("Paste this into GitHub, GitLab or a server's ~/.ssh/authorized_keys. Never share the private key.")
            }

            Section("Used by") {
                if usedBy.isEmpty {
                    Text("No hosts use this key yet.").foregroundStyle(.secondary)
                }
                ForEach(usedBy) { Text($0.pattern) }
                if key.hasPrivate {
                    Menu("Use with Host…") {
                        ForEach(store.hosts.filter { $0.kind == .host }) { host in
                            Button(host.pattern) { useWith(host) }
                        }
                    }
                    .fixedSize()
                }
            }

            Section("Actions") {
                if key.hasPrivate {
                    Button("Add to Agent & Keychain", systemImage: "lock.shield") {
                        Shell.runInTerminal("/usr/bin/ssh-add --apple-use-keychain \(Shell.quote(key.path))")
                    }
                    .help("Unlocks the key once and remembers the passphrase in your macOS Keychain")
                    Button("Change Passphrase…", systemImage: "key.horizontal") {
                        Shell.runInTerminal("/usr/bin/ssh-keygen -p -f \(Shell.quote(key.path))")
                    }
                }
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: key.path)])
                }
                Button("Move to Trash…", systemImage: "trash", role: .destructive) { confirmTrash = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(key.name)
        .confirmationDialog("Move \(key.name) to the Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) { KeyStore.shared.trash(key) }
        } message: {
            Text(usedBy.isEmpty
                 ? "Both halves of the key pair go to the Trash, so you can still recover them."
                 : "\(usedBy.count) host(s) still use this key and won't be able to log in with it.")
        }
    }

    private func useWith(_ host: HostBlock) {
        guard let i = store.config.blocks.firstIndex(where: { $0.id == host.id }) else { return }
        store.config.blocks[i].set("IdentityFile", Shell.abbreviate(key.path))
    }
}

struct GenerateKeySheet: View {
    var onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = KeyStore.KeyType.ed25519
    @State private var comment = "\(NSUserName())@\(Host.current().localizedName ?? "mac")"
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var working = false

    private var nameTaken: Bool {
        FileManager.default.fileExists(atPath: KeyStore.shared.directory.appending(path: name).path)
    }

    private var nameValid: Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && !name.hasSuffix(".pub") && !nameTaken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("File name", text: $name, prompt: Text("id_ed25519_github"))
                    if nameTaken { Text("That file already exists in ~/.ssh.").foregroundStyle(.red).font(.caption) }
                    Picker("Type", selection: $type) {
                        ForEach(KeyStore.KeyType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Comment", text: $comment)
                } footer: {
                    Text("Ed25519 is the modern default. Pick RSA only for very old servers.")
                }
                Section {
                    SecureField("Passphrase", text: $passphrase)
                    SecureField("Confirm", text: $confirm)
                } header: {
                    Text("Passphrase")
                } footer: {
                    Text(passphrase.isEmpty
                         ? "Leaving it empty means anyone who gets the file can use the key."
                         : "Use “Add to Agent & Keychain” afterwards so you don't have to type it each time.")
                }
            }
            .formStyle(.grouped)
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Generate") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameValid || passphrase != confirm || working)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear { name = defaultName() }
    }

    private func defaultName() -> String {
        var candidate = "id_ed25519"
        var n = 2
        while FileManager.default.fileExists(atPath: KeyStore.shared.directory.appending(path: candidate).path) {
            candidate = "id_ed25519_\(n)"; n += 1
        }
        return candidate
    }

    private func generate() {
        working = true
        Task {
            let path = await KeyStore.shared.generate(name: name, type: type, comment: comment, passphrase: passphrase)
            working = false
            dismiss()
            if let path { onCreate(path) }
        }
    }
}
