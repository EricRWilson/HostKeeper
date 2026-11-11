import Foundation

/// Where HostKeeper reads and writes.
///
/// Release builds (the downloadable app) use your real `~/.ssh`. Debug builds (Xcode ⌘R, `swift run`) use a
/// practice folder, so development can never damage your real config or keys. Set `HOSTKEEPER_SSH_DIR`
/// to point either kind of build somewhere else.
enum Paths {
    static let realSSHDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh")

    static let practiceDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/HostKeeper-Dev/ssh")

    static let sshDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["HOSTKEEPER_SSH_DIR"], !custom.isEmpty {
            return URL(filePath: Shell.expandTilde(custom))
        }
        #if DEBUG
        return practiceDirectory
        #else
        return realSSHDirectory
        #endif
    }()

    static var config: URL { sshDirectory.appending(path: "config") }

    static var isPractice: Bool { sshDirectory.standardizedFileURL != realSSHDirectory.standardizedFileURL }

    /// ssh only reads ~/.ssh/config by default, so point it at the practice config when needed.
    static var sshConfigFlag: String {
        isPractice ? "-F \(Shell.quote(config.path)) " : ""
    }

    /// Creates the practice folder with a sample config the first time a debug build runs.
    static func preparePracticeFolder() {
        guard isPractice else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: sshDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard !fm.fileExists(atPath: config.path) else { return }
        try? sampleConfig.write(to: config, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
    }

    private static let sampleConfig = """
    # Practice config for HostKeeper development builds. Edit freely; your real ~/.ssh is untouched.
    Host *
        AddKeysToAgent yes
        ServerAliveInterval 60

    Host web
        # hostkeeper:folder Work
        # hostkeeper:tags prod, linux
        # hostkeeper:note Example production web server
        HostName 203.0.113.10
        User deploy
        ProxyJump bastion

    Host bastion
        # hostkeeper:folder Work
        # hostkeeper:tags prod
        HostName bastion.example.com
        User admin
        Port 2222

    Host pi
        # hostkeeper:folder Home Lab
        # hostkeeper:tags raspberry-pi, linux
        HostName raspberrypi.local
        User pi

    Host github.com
        # hostkeeper:tags git
        User git
        IdentitiesOnly yes

    """
}
