import Foundation
import Observation
import SSHConfigKit

@MainActor @Observable
final class ConfigStore {
    static let shared = ConfigStore()

    let url = Paths.config
    var config = SSHConfig.parse("")
    private(set) var savedText = ""
    var errorMessage: String?

    var isDirty: Bool { config.render() != savedText }
    var hosts: [HostBlock] { config.blocks.filter { $0.kind != .global } }

    var backupDirectory: URL { url.deletingLastPathComponent().appending(path: "hostkeeper-backups") }

    /// Folders with no hosts yet only exist here; folders in use are read from the config itself.
    private var emptyFolders: [String] = UserDefaults.standard.stringArray(forKey: "emptyFolders") ?? [] {
        didSet { UserDefaults.standard.set(emptyFolders, forKey: "emptyFolders") }
    }

    var folders: [String] {
        Set(hosts.map(\.folder).filter { !$0.isEmpty } + emptyFolders)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func addFolder(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !folders.contains(name) else { return }
        emptyFolders.append(name)
    }

    func renameFolder(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != old else { return }
        for i in config.blocks.indices where config.blocks[i].folder == old { config.blocks[i].folder = new }
        emptyFolders.removeAll { $0 == old }
        if !hosts.contains(where: { $0.folder == new }) { emptyFolders.append(new) }
    }

    /// Removes the folder; its hosts move back to "Unfiled" rather than being deleted.
    func deleteFolder(_ name: String) {
        for i in config.blocks.indices where config.blocks[i].folder == name { config.blocks[i].folder = "" }
        emptyFolders.removeAll { $0 == name }
    }

    func move(_ id: UUID, toFolder folder: String) {
        guard let i = config.blocks.firstIndex(where: { $0.id == id }), config.blocks[i].kind != .global else { return }
        let old = config.blocks[i].folder
        config.blocks[i].folder = folder
        emptyFolders.removeAll { $0 == folder }
        if !old.isEmpty, !hosts.contains(where: { $0.folder == old }) { emptyFolders.append(old) }
    }

    var hostTags: [String] {
        HostBlock.normalize(hosts.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func addTag(_ tag: String, to id: UUID) {
        guard let i = config.blocks.firstIndex(where: { $0.id == id }), config.blocks[i].kind != .global else { return }
        config.blocks[i].tags.append(tag)
    }

    /// Renames or (with an empty name) removes a tag on every host and key.
    func renameTag(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespaces)
        for i in config.blocks.indices where config.blocks[i].hasTag(old) {
            config.blocks[i].tags = config.blocks[i].tags.compactMap {
                $0.caseInsensitiveCompare(old) == .orderedSame ? (new.isEmpty ? nil : new) : $0
            }
        }
        if new.isEmpty { KeyStore.shared.removeTag(old) } else { KeyStore.shared.renameTag(old, to: new) }
    }

    func backups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("config-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Loads a backup into the editor as unsaved changes, so nothing on disk changes until you save.
    func restore(_ backup: URL) {
        guard let text = try? String(contentsOf: backup, encoding: .utf8) else {
            errorMessage = "Couldn't read \(backup.lastPathComponent)"
            return
        }
        config = SSHConfig.parse(text)
    }

    private init() {
        Paths.preparePracticeFolder()
        load()
    }

    func load() {
        do {
            savedText = FileManager.default.fileExists(atPath: url.path)
                ? try String(contentsOf: url, encoding: .utf8)
                : ""
            config = SSHConfig.parse(savedText)
        } catch {
            errorMessage = "Couldn't read \(url.path): \(error.localizedDescription)"
        }
    }

    /// Validates with `ssh -G`, keeps a timestamped backup of the current file (last 30), then writes atomically with 0600 permissions.
    @discardableResult
    func save() -> Bool {
        let text = config.render()
        if let problem = validate(text) {
            errorMessage = "ssh rejected the new config, so nothing was saved:\n\n\(problem)"
            return false
        }
        let fm = FileManager.default
        do {
            let dir = url.deletingLastPathComponent()
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            if fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let stamp = Date.now.formatted(.verbatim(
                    "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                    timeZone: .current, calendar: .current))
                let backup = backupDirectory.appending(path: "config-\(stamp)")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: url, to: backup)
                for old in backups().dropFirst(30) { try? fm.removeItem(at: old) }
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            savedText = text
            return true
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }

    func addHost(inFolder folder: String = "") -> UUID {
        var alias = "new-host"
        var n = 2
        while hosts.contains(where: { $0.pattern == alias }) { alias = "new-host-\(n)"; n += 1 }
        separateLastBlock()
        var block = HostBlock.newHost(alias)
        block.folder = folder
        config.blocks.append(block)
        return block.id
    }

    func duplicate(_ id: UUID) -> UUID? {
        guard let i = config.blocks.firstIndex(where: { $0.id == id }), config.blocks[i].kind != .global else { return nil }
        let source = config.blocks[i]
        let copy = HostBlock(
            kind: source.kind,
            pattern: source.pattern + "-copy",
            lines: source.lines.map { ConfigLine(key: $0.key, value: $0.value) }
        )
        config.blocks.insert(copy, at: i + 1)
        return copy.id
    }

    func delete(_ id: UUID) {
        config.blocks.removeAll { $0.id == id && $0.kind != .global }
    }

    /// Ensures a blank line before a newly appended block.
    private func separateLastBlock() {
        guard let last = config.blocks.indices.last else { return }
        let block = config.blocks[last]
        if block.kind == .global && block.lines.isEmpty { return }
        if block.lines.last.map({ !$0.isOption && $0.value.trimmingCharacters(in: .whitespaces).isEmpty }) != true {
            config.blocks[last].lines.append(.verbatim(""))
        }
    }

    /// Writes the current (possibly unsaved) config to a temp file, for running ssh against unsaved edits.
    func writeTempConfig() -> URL? {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "hostkeeper-\(UUID().uuidString)")
        guard (try? config.render().write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        return tmp
    }

    private func validate(_ text: String) -> String? {
        // `Match exec` would run arbitrary commands during validation, so skip it for those configs.
        if config.blocks.contains(where: { $0.kind == .match && $0.pattern.lowercased().contains("exec") }) { return nil }
        let tmp = FileManager.default.temporaryDirectory.appending(path: "hostkeeper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (try? text.write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return nil }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ssh")
        process.arguments = ["-G", "-F", tmp.path, "hostkeeper-validate"]
        let err = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = err
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return message.replacingOccurrences(of: tmp.path, with: "config")
    }
}
