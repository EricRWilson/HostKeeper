import Foundation
import Observation
import SSHConfigKit

struct SSHKey: Identifiable, Hashable, Sendable {
    var id: String { path }
    /// Path to the private key, or to the .pub file when only the public half exists.
    var path: String
    var hasPrivate: Bool
    var publicKey: String
    var type = ""
    var bits = ""
    var fingerprint = ""
    var comment = ""
    var permissions: Int = 0

    var name: String { (path as NSString).lastPathComponent }
    var publicPath: String { hasPrivate ? path + ".pub" : path }
    var permissionsTooOpen: Bool { hasPrivate && permissions & 0o077 != 0 }
}

@MainActor @Observable
final class KeyStore {
    static let shared = KeyStore()

    let directory = Paths.sshDirectory
    private(set) var keys: [SSHKey] = []
    var errorMessage: String?

    /// Key files can't carry comments, so key tags are remembered by HostKeeper, keyed by file path.
    private(set) var keyTags: [String: [String]] =
        (UserDefaults.standard.dictionary(forKey: "keyTags") as? [String: [String]]) ?? [:] {
        didSet { UserDefaults.standard.set(keyTags, forKey: "keyTags") }
    }

    func tags(for key: SSHKey) -> [String] { keyTags[key.path] ?? [] }

    func setTags(_ tags: [String], for key: SSHKey) {
        let clean = HostBlock.normalize(tags)
        keyTags[key.path] = clean.isEmpty ? nil : clean
    }

    func renameTag(_ old: String, to new: String) {
        for (path, tags) in keyTags {
            keyTags[path] = HostBlock.normalize(tags.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 })
        }
    }

    func removeTag(_ tag: String) {
        for (path, tags) in keyTags {
            let kept = tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
            keyTags[path] = kept.isEmpty ? nil : kept
        }
    }

    nonisolated private static let ignored: Set<String> = [
        "config", "known_hosts", "known_hosts.old", "authorized_keys", "authorized_keys2", "environment", "rc",
    ]

    private init() { reload() }

    func reload() {
        let dir = directory
        Task.detached {
            let found = Self.scan(dir)
            await MainActor.run { self.keys = found }
        }
    }

    nonisolated private static func scan(_ dir: URL) -> [SSHKey] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        let nameSet = Set(names)
        var keys: [SSHKey] = []

        for name in names.sorted() where !ignored.contains(name) && !name.hasPrefix(".") {
            let path = dir.appending(path: name).path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }

            if name.hasSuffix(".pub") {
                // Public key on its own; pairs are handled from the private side.
                guard !nameSet.contains(String(name.dropLast(4))) else { continue }
                keys.append(describe(SSHKey(path: path, hasPrivate: false, publicKey: read(path))))
            } else if nameSet.contains(name + ".pub") || looksLikePrivateKey(path) {
                let pub = nameSet.contains(name + ".pub") ? read(path + ".pub") : ""
                keys.append(describe(SSHKey(path: path, hasPrivate: true, publicKey: pub)))
            }
        }
        return keys
    }

    nonisolated private static func read(_ path: String) -> String {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only peeks at the PEM header line; key material is never loaded.
    nonisolated private static func looksLikePrivateKey(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: handle.readData(ofLength: 64), as: UTF8.self)
        return head.hasPrefix("-----BEGIN") && head.contains("PRIVATE KEY")
    }

    nonisolated private static func describe(_ key: SSHKey) -> SSHKey {
        var key = key
        let attrs = try? FileManager.default.attributesOfItem(atPath: key.path)
        key.permissions = (attrs?[.posixPermissions] as? Int) ?? 0
        // e.g. "256 SHA256:abc… you@mac (ED25519)"
        let target = key.publicKey.isEmpty ? key.path : key.publicPath
        let result = Shell.run("/usr/bin/ssh-keygen", ["-l", "-f", target])
        let line = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !line.isEmpty else { return key }
        var parts = line.split(separator: " ").map(String.init)
        if parts.count >= 3 {
            key.bits = parts.removeFirst()
            key.fingerprint = parts.removeFirst()
            if let last = parts.last, last.hasPrefix("(") {
                key.type = String(last.dropFirst().dropLast())
                parts.removeLast()
            }
            key.comment = parts.joined(separator: " ")
        }
        return key
    }

    enum KeyType: String, CaseIterable, Identifiable {
        case ed25519 = "Ed25519", rsa = "RSA 4096", ecdsa = "ECDSA 521"
        var id: String { rawValue }
        var args: [String] {
            switch self {
            case .ed25519: ["-t", "ed25519"]
            case .rsa: ["-t", "rsa", "-b", "4096"]
            case .ecdsa: ["-t", "ecdsa", "-b", "521"]
            }
        }
    }

    /// Creates a new key pair with ssh-keygen. Returns the private key path on success.
    func generate(name: String, type: KeyType, comment: String, passphrase: String) async -> String? {
        let path = directory.appending(path: name).path
        guard !FileManager.default.fileExists(atPath: path) else {
            errorMessage = "A file named \(name) already exists in ~/.ssh."
            return nil
        }
        let args = type.args + ["-f", path, "-C", comment, "-N", passphrase, "-q"]
        let result = await Task.detached { Shell.run("/usr/bin/ssh-keygen", args) }.value
        guard result.status == 0 else {
            errorMessage = "ssh-keygen failed: \(result.error)"
            return nil
        }
        reload()
        return path
    }

    /// Copies a key file (and its .pub if next to it) into ~/.ssh with safe permissions.
    func importKey(from url: URL) {
        let fm = FileManager.default
        let dest = directory.appending(path: url.lastPathComponent)
        do {
            guard !fm.fileExists(atPath: dest.path) else {
                errorMessage = "~/.ssh/\(url.lastPathComponent) already exists."
                return
            }
            try fm.copyItem(at: url, to: dest)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
            let pub = URL(filePath: url.path + ".pub")
            let destPub = URL(filePath: dest.path + ".pub")
            if fm.fileExists(atPath: pub.path), !fm.fileExists(atPath: destPub.path) {
                try fm.copyItem(at: pub, to: destPub)
                try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destPub.path)
            }
        } catch {
            errorMessage = "Couldn't import: \(error.localizedDescription)"
        }
        reload()
    }

    func fixPermissions(_ key: SSHKey) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        reload()
    }

    /// Moves the key (and its .pub) to the Trash so it can still be recovered.
    func trash(_ key: SSHKey) {
        let fm = FileManager.default
        do {
            try fm.trashItem(at: URL(filePath: key.path), resultingItemURL: nil)
            if key.hasPrivate, fm.fileExists(atPath: key.publicPath) {
                try fm.trashItem(at: URL(filePath: key.publicPath), resultingItemURL: nil)
            }
            keyTags[key.path] = nil
        } catch {
            errorMessage = "Couldn't move to Trash: \(error.localizedDescription)"
        }
        reload()
    }
}
