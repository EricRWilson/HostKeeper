import Foundation

/// One line inside a block: either a `Key value` option or a verbatim comment/blank line.
/// Lines that are never edited are written back exactly as they were read.
public struct ConfigLine: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var key: String
    public var value: String
    private let original: String?
    private let originalKey: String
    private let originalValue: String

    public var isOption: Bool { !key.isEmpty }

    public init(key: String, value: String, original: String? = nil) {
        self.key = key
        self.value = value
        self.original = original
        self.originalKey = key
        self.originalValue = value
    }

    public static func verbatim(_ text: String) -> ConfigLine {
        ConfigLine(key: "", value: text, original: text)
    }

    func render(indent: String) -> String {
        if let original, key == originalKey, value == originalValue { return original }
        return isOption ? "\(indent)\(key) \(SSHConfig.quote(value))" : value
    }
}

public struct HostBlock: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case global, host = "Host", match = "Match" }

    public let id = UUID()
    public var kind: Kind
    public var pattern: String
    public var lines: [ConfigLine]
    private let originalHeader: String?
    private let originalPattern: String

    public init(kind: Kind, pattern: String, lines: [ConfigLine] = [], originalHeader: String? = nil) {
        self.kind = kind
        self.pattern = pattern
        self.lines = lines
        self.originalHeader = originalHeader
        self.originalPattern = pattern
    }

    public static func newHost(_ alias: String) -> HostBlock {
        HostBlock(kind: .host, pattern: alias, lines: [])
    }

    /// The first alias in the pattern, usable as `ssh <alias>` when it has no wildcards.
    public var connectAlias: String? {
        guard kind == .host, let first = pattern.split(separator: " ").first else { return nil }
        let alias = String(first)
        return alias.contains(where: { "*?!".contains($0) }) ? nil : alias
    }

    public var options: [ConfigLine] { lines.filter(\.isOption) }

    public func value(_ key: String) -> String {
        lines.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value ?? ""
    }

    /// Sets a single-valued option. An empty value removes it.
    public mutating func set(_ key: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let i = lines.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            if trimmed.isEmpty { lines.remove(at: i) } else { lines[i].value = trimmed }
        } else if !trimmed.isEmpty {
            let insertAt = (lines.lastIndex(where: \.isOption) ?? -1) + 1
            lines.insert(ConfigLine(key: key, value: trimmed), at: insertAt)
        }
    }

    /// Folder name, stored as a `# hostkeeper:folder <name>` comment so it travels with the file and ssh ignores it.
    public var folder: String {
        get { meta("folder") }
        set { setMeta("folder", newValue) }
    }

    /// Free-form note, stored as a `# hostkeeper:note <text>` comment.
    public var note: String {
        get { meta("note") }
        set { setMeta("note", newValue) }
    }

    /// Tags, stored as a `# hostkeeper:tags prod, web` comment.
    public var tags: [String] {
        get { Self.parseTags(meta("tags")) }
        set { setMeta("tags", Self.normalize(newValue).joined(separator: ", ")) }
    }

    public static func parseTags(_ text: String) -> [String] {
        normalize(text.split(separator: ",").map(String.init))
    }

    /// Trims, drops empties and removes case-insensitive duplicates, keeping the first spelling.
    public static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap {
            let tag = $0.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }
    }

    public func hasTag(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    private static let metaPrefix = "# hostkeeper:"

    private func metaIndex(_ name: String) -> Int? {
        lines.firstIndex {
            !$0.isOption && $0.value.trimmingCharacters(in: .whitespaces).hasPrefix(Self.metaPrefix + name + " ")
        }
    }

    private func meta(_ name: String) -> String {
        guard let i = metaIndex(name) else { return "" }
        let text = lines[i].value.trimmingCharacters(in: .whitespaces)
        return String(text.dropFirst(Self.metaPrefix.count + name.count + 1))
    }

    private mutating func setMeta(_ name: String, _ value: String) {
        let clean = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let text = "\(kind == .global ? "" : indent)\(Self.metaPrefix)\(name) \(clean)"
        switch (metaIndex(name), clean.isEmpty) {
        case (let i?, true): lines.remove(at: i)
        case (let i?, false): lines[i].value = text
        case (nil, false): lines.insert(.verbatim(text), at: 0)
        case (nil, true): break
        }
    }

    var indent: String {
        guard let first = lines.first(where: \.isOption) else { return kind == .global ? "" : "    " }
        let rendered = first.render(indent: "")
        return String(rendered.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    func render() -> [String] {
        var out: [String] = []
        if kind != .global {
            if let originalHeader, pattern == originalPattern {
                out.append(originalHeader)
            } else {
                out.append("\(kind.rawValue) \(pattern)")
            }
        }
        let indent = self.indent.isEmpty && kind != .global ? "    " : self.indent
        out += lines.map { $0.render(indent: indent) }
        return out
    }
}

public struct SSHConfig: Sendable {
    public var blocks: [HostBlock]
    var trailingNewline: Bool

    public static func parse(_ text: String) -> SSHConfig {
        var rawLines = text.components(separatedBy: "\n")
        let trailingNewline = text.hasSuffix("\n")
        if trailingNewline || text.isEmpty { rawLines.removeLast() }

        var blocks = [HostBlock(kind: .global, pattern: "")]
        for raw in rawLines {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            guard let (key, value) = splitOption(line) else {
                blocks[blocks.count - 1].lines.append(.verbatim(line))
                continue
            }
            switch key.lowercased() {
            case "host":
                blocks.append(HostBlock(kind: .host, pattern: value, originalHeader: line))
            case "match":
                blocks.append(HostBlock(kind: .match, pattern: value, originalHeader: line))
            default:
                blocks[blocks.count - 1].lines.append(ConfigLine(key: key, value: value, original: line))
            }
        }
        return SSHConfig(blocks: blocks, trailingNewline: trailingNewline || text.isEmpty)
    }

    public func render() -> String {
        let lines = blocks.flatMap { $0.render() }
        let body = lines.joined(separator: "\n")
        return trailingNewline && !body.isEmpty ? body + "\n" : body
    }

    /// Splits `Key value`, `Key=value` or `Key = value`. Returns nil for comments and blank lines.
    static func splitOption(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        guard let keyEnd = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "=" }) else {
            return (trimmed, "")
        }
        let key = String(trimmed[..<keyEnd])
        var rest = trimmed[keyEnd...].drop(while: { $0 == " " || $0 == "\t" })
        if rest.first == "=" { rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" }) }
        var value = String(rest)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\""), !value.dropFirst().dropLast().contains("\"") {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }

    static func quote(_ value: String) -> String {
        value.contains(" ") && !value.hasPrefix("\"") ? "\"\(value)\"" : value
    }
}
