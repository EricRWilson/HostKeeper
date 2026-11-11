import Foundation

/// Plain-language explanations of ssh_config keywords, shown in Help and as tooltips on the host page.
struct OptionInfo: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case basics = "Basics"
        case keys = "Keys & Login"
        case forwarding = "Port Forwarding"
        case jumping = "Jump Hosts & Proxies"
        case connection = "Keeping Connections Alive"
        case security = "Security"
        case session = "Session & Commands"
        case files = "Files & Organization"
    }

    let key: String
    let category: Category
    let summary: String
    let example: String
    var id: String { key }
}

enum OptionReference {
    static func info(for key: String) -> OptionInfo? {
        byKey[key.lowercased()]
    }

    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key.lowercased(), $0) })

    static let all: [OptionInfo] = [
        // Basics
        OptionInfo(key: "Host", category: .basics,
                   summary: "Starts a host entry. The names after it are what you type after ssh. Use several names separated by spaces, or * and ? as wildcards to apply settings to many hosts (Host * applies to every host).",
                   example: "Host web web.prod"),
        OptionInfo(key: "Match", category: .basics,
                   summary: "Like Host, but applies its settings only when conditions are true, such as the user, the real host name, or the result of a command.",
                   example: "Match host *.corp user admin"),
        OptionInfo(key: "HostName", category: .basics,
                   summary: "The real address to connect to: a domain name or IP address. If you leave it out, ssh uses the Host name itself.",
                   example: "HostName 192.168.1.50"),
        OptionInfo(key: "User", category: .basics,
                   summary: "The username to log in as on the server. Without it, ssh uses your Mac username.",
                   example: "User ubuntu"),
        OptionInfo(key: "Port", category: .basics,
                   summary: "The port the server's SSH service listens on. The default is 22.",
                   example: "Port 2222"),

        // Keys & Login
        OptionInfo(key: "IdentityFile", category: .keys,
                   summary: "The private key to log in with. Point it at the private file, not the .pub. You can list it more than once to try several keys.",
                   example: "IdentityFile ~/.ssh/id_ed25519"),
        OptionInfo(key: "IdentitiesOnly", category: .keys,
                   summary: "When yes, ssh only offers the IdentityFile key(s) you listed instead of every key in your agent. Fixes “Too many authentication failures” errors.",
                   example: "IdentitiesOnly yes"),
        OptionInfo(key: "AddKeysToAgent", category: .keys,
                   summary: "When yes, a key is added to the ssh agent the first time you use it, so you only type its passphrase once per login session.",
                   example: "AddKeysToAgent yes"),
        OptionInfo(key: "UseKeychain", category: .keys,
                   summary: "Mac only. When yes, ssh stores key passphrases in your macOS Keychain so you never have to type them again. Often put under Host *.",
                   example: "UseKeychain yes"),
        OptionInfo(key: "PreferredAuthentications", category: .keys,
                   summary: "The order of login methods to try, for example keys first, then a password.",
                   example: "PreferredAuthentications publickey,password"),
        OptionInfo(key: "PasswordAuthentication", category: .keys,
                   summary: "Whether ssh may ask for a password. Set no to make sure only keys are used.",
                   example: "PasswordAuthentication no"),
        OptionInfo(key: "CertificateFile", category: .keys,
                   summary: "An SSH certificate to present alongside your key. Used by organizations that sign keys centrally.",
                   example: "CertificateFile ~/.ssh/id_ed25519-cert.pub"),

        // Forwarding
        OptionInfo(key: "LocalForward", category: .forwarding,
                   summary: "Opens a port on your Mac that tunnels to an address reachable from the server. Handy for reaching a database or web admin page that's only open on the server.",
                   example: "LocalForward 5432 localhost:5432"),
        OptionInfo(key: "RemoteForward", category: .forwarding,
                   summary: "The reverse of LocalForward: opens a port on the server that tunnels back to something on your Mac.",
                   example: "RemoteForward 8080 localhost:3000"),
        OptionInfo(key: "DynamicForward", category: .forwarding,
                   summary: "Turns the connection into a SOCKS proxy on your Mac, so apps set to use it browse through the server.",
                   example: "DynamicForward 1080"),
        OptionInfo(key: "ForwardAgent", category: .forwarding,
                   summary: "Lets the server use the keys in your Mac's ssh agent, e.g. to git pull from GitHub on the server. Only enable it for servers you trust; their admins can use your keys while you're connected.",
                   example: "ForwardAgent yes"),
        OptionInfo(key: "ForwardX11", category: .forwarding,
                   summary: "Shows graphical Linux apps from the server on your Mac (needs XQuartz installed).",
                   example: "ForwardX11 yes"),
        OptionInfo(key: "ExitOnForwardFailure", category: .forwarding,
                   summary: "When yes, ssh quits if a requested port forward can't be set up, instead of connecting without it.",
                   example: "ExitOnForwardFailure yes"),

        // Jump hosts
        OptionInfo(key: "ProxyJump", category: .jumping,
                   summary: "Connects through another host first (a “bastion” or “jump box”). Use a Host name from your config, or user@host:port. Separate several with commas.",
                   example: "ProxyJump bastion"),
        OptionInfo(key: "ProxyCommand", category: .jumping,
                   summary: "An advanced alternative to ProxyJump: a command whose input and output carry the connection. %h is the host and %p the port.",
                   example: "ProxyCommand ssh -W %h:%p bastion"),

        // Connection
        OptionInfo(key: "ServerAliveInterval", category: .connection,
                   summary: "Sends a small keep-alive message every this many seconds. Stops idle connections being dropped by routers or Wi-Fi changes.",
                   example: "ServerAliveInterval 60"),
        OptionInfo(key: "ServerAliveCountMax", category: .connection,
                   summary: "How many keep-alive messages may go unanswered before ssh gives up on the connection.",
                   example: "ServerAliveCountMax 3"),
        OptionInfo(key: "ConnectTimeout", category: .connection,
                   summary: "How many seconds to wait while connecting before giving up.",
                   example: "ConnectTimeout 10"),
        OptionInfo(key: "ControlMaster", category: .connection,
                   summary: "Reuses one connection for several ssh sessions to the same host, so later ones open instantly. Use with ControlPath and ControlPersist.",
                   example: "ControlMaster auto"),
        OptionInfo(key: "ControlPath", category: .connection,
                   summary: "Where the shared connection's socket file lives. %C makes a unique name per host.",
                   example: "ControlPath ~/.ssh/cm-%C"),
        OptionInfo(key: "ControlPersist", category: .connection,
                   summary: "How long a shared connection stays open in the background after you log out.",
                   example: "ControlPersist 10m"),
        OptionInfo(key: "Compression", category: .connection,
                   summary: "Compresses traffic. Helps on slow connections, slightly slower on fast ones.",
                   example: "Compression yes"),

        // Security
        OptionInfo(key: "StrictHostKeyChecking", category: .security,
                   summary: "What to do with a server you haven't connected to before. ask (default) prompts you, accept-new trusts new servers but still warns if a known one changes, no trusts everything (unsafe).",
                   example: "StrictHostKeyChecking accept-new"),
        OptionInfo(key: "UserKnownHostsFile", category: .security,
                   summary: "The file where trusted server fingerprints are stored. /dev/null means remember nothing (only for throwaway test machines).",
                   example: "UserKnownHostsFile ~/.ssh/known_hosts"),
        OptionInfo(key: "HashKnownHosts", category: .security,
                   summary: "Stores server names in known_hosts in a scrambled form so others reading the file can't see where you connect.",
                   example: "HashKnownHosts yes"),
        OptionInfo(key: "HostKeyAlias", category: .security,
                   summary: "The name to file this server's fingerprint under. Useful when several hosts share one address or port forward.",
                   example: "HostKeyAlias myrouter"),

        // Session
        OptionInfo(key: "RequestTTY", category: .session,
                   summary: "Whether to open an interactive terminal. Use yes or force with RemoteCommand when the command needs a terminal (like tmux).",
                   example: "RequestTTY yes"),
        OptionInfo(key: "RemoteCommand", category: .session,
                   summary: "A command to run on the server right after logging in, instead of a normal shell.",
                   example: "RemoteCommand tmux new -A -s main"),
        OptionInfo(key: "SetEnv", category: .session,
                   summary: "Sends environment variables to the server (the server must allow them).",
                   example: "SetEnv LANG=en_US.UTF-8"),
        OptionInfo(key: "SendEnv", category: .session,
                   summary: "Passes environment variables from your Mac to the server (the server must allow them).",
                   example: "SendEnv LANG LC_*"),
        OptionInfo(key: "LogLevel", category: .session,
                   summary: "How much ssh prints about what it's doing. QUIET hides warnings; DEBUG helps troubleshoot.",
                   example: "LogLevel ERROR"),

        // Files
        OptionInfo(key: "Include", category: .files,
                   summary: "Reads more settings from other files. Lets you split a big config into pieces, or load configs other apps create (like OrbStack or Colima).",
                   example: "Include ~/.ssh/config.d/*"),
    ]
}
