import AppKit
import Foundation

enum Shell {
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a command in a new Terminal window via a temporary .command file
    /// (this avoids needing Automation permission to script Terminal).
    static func runInTerminal(_ command: String) {
        let file = FileManager.default.temporaryDirectory.appending(path: "hostkeeper-\(UUID().uuidString).command")
        let script = "#!/bin/zsh\nrm -f \(quote(file.path))\nclear\n\(command)\n"
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            NSSound.beep()
        }
    }

    struct Result: Sendable {
        var status: Int32
        var output: String
        var error: String
    }

    /// Runs a program and waits for it. Call from a background task for anything that may be slow.
    static func run(_ path: String, _ args: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Result(status: -1, output: "", error: error.localizedDescription) }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errData, as: UTF8.self)
        )
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    static func expandTilde(_ path: String) -> String {
        path.hasPrefix("~/") ? home + path.dropFirst(1) : path
    }

    static func abbreviate(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
