import Observation
import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case welcome = "Welcome"
    case hosts = "Hosts"
    case folders = "Folders & Notes"
    case tags = "Tags & Search"
    case keys = "SSH Keys"
    case connecting = "Connecting & Testing"
    case saving = "Saving & Backups"
    case menuBar = "Menu Bar"
    case updates = "Updates"
    case options = "Option Reference"
    case troubleshooting = "Troubleshooting"
    case shortcuts = "Keyboard Shortcuts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .welcome: "hand.wave"
        case .hosts: "server.rack"
        case .folders: "folder"
        case .tags: "tag"
        case .keys: "key"
        case .connecting: "terminal"
        case .saving: "clock.arrow.circlepath"
        case .menuBar: "menubar.rectangle"
        case .updates: "arrow.down.circle"
        case .options: "list.bullet.rectangle"
        case .troubleshooting: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        }
    }
}

/// Lets any screen open Help at a particular page.
@MainActor @Observable
final class HelpRouter {
    static let shared = HelpRouter()
    var topic: HelpTopic? = .welcome
    var optionSearch = ""
}

struct OpenHelpButton: View {
    var topic: HelpTopic
    var option: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Help", systemImage: "questionmark.circle") {
            HelpRouter.shared.topic = topic
            HelpRouter.shared.optionSearch = option ?? ""
            openWindow(id: "help")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("Open Help: \(topic.rawValue)")
    }
}

struct HelpView: View {
    @Bindable private var router = HelpRouter.shared

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $router.topic) { topic in
                Label(topic.rawValue, systemImage: topic.icon).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Text("HostKeeper \(AppVersion.display)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(8)
            }
        } detail: {
            if router.topic == .options {
                OptionReferenceView(search: $router.optionSearch)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        page(router.topic ?? .welcome)
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("HostKeeper Help")
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder private func page(_ topic: HelpTopic) -> some View {
        switch topic {
        case .welcome:
            heading("Welcome to HostKeeper")
            para("HostKeeper is a free editor for your SSH config file, ~/.ssh/config. That file is where the ssh command built into macOS looks up shortcuts for the servers you connect to.")
            para("With a host saved, typing ssh web in Terminal is all it takes, instead of ssh -i ~/.ssh/key -p 2222 deploy@203.0.113.7.")
            subheading("You don't need HostKeeper running to use SSH")
            para("HostKeeper only edits the file. ssh reads it on its own every time it runs, so your hosts keep working when HostKeeper is closed or even deleted.")
            subheading("Getting started")
            step(1, "Click + in the toolbar to add a host.")
            step(2, "Fill in the HostName (address), User and, if you use one, the key.")
            step(3, "Press ⌘S to save, then click Test Connection or Open in Terminal.")

        case .hosts:
            heading("Hosts")
            para("Each host in the sidebar is one Host block in your config. Click it to edit it on the right.")
            subheading("The fields")
            bullet("Host", "The nickname(s) you type after ssh. Several names separated by spaces all work. * and ? are wildcards: Host * applies to every server, Host *.lan to every name ending in .lan.")
            bullet("Folder & Notes", "Organize and describe the host. See Folders & Notes.")
            bullet("HostName", "The real address: a domain name or IP address.")
            bullet("User", "The username on the server. Leave it empty to use your Mac username.")
            bullet("Port", "Leave empty for the standard port 22.")
            bullet("IdentityFile", "The private key to log in with. The Key menu lists the keys in ~/.ssh.")
            bullet("ProxyJump", "Another host to connect through first, for servers you can't reach directly.")
            bullet("Behavior", "Agent forwarding, using only the listed key, remembering keys and keep-alives. “Default” means the setting isn't written, so ssh's normal behavior or a Host * entry applies.")
            bullet("Other options", "Any other ssh setting. Hover a name for an explanation, or see Option Reference for all of them.")
            subheading("Global settings and Match blocks")
            para("Settings above the first Host line apply to everything; they appear as “Global settings” at the top of the sidebar. Match blocks are shown with a Match label and work the same way, with conditions instead of names.")
            subheading("Order matters")
            para("For each setting, ssh uses the first value it finds. Put specific hosts above general ones like Host *. New hosts are added at the end of the file.")
            subheading("Adding, duplicating, deleting")
            para("Use + (⌘N), the Duplicate button, or right-click a host. Deleting only takes effect when you save, and the previous file is kept in Backups.")

        case .folders:
            heading("Folders & Notes")
            para("Folders are for keeping things tidy, like Work, Home Lab or Clients. They don't change how ssh behaves.")
            subheading("Using folders")
            step(1, "Choose + ▸ New Folder… and give it a name.")
            step(2, "Drag a host onto the folder name, right-click a host and choose Move to Folder, or pick the folder on the host's page.")
            step(3, "Click the arrow beside a folder to collapse it. Right-click a folder to rename it or delete it.")
            para("Deleting a folder never deletes hosts; they move back to Unfiled.")
            subheading("How they're saved")
            para("Folders and notes are saved as comment lines inside the host, which ssh ignores:")
            code("Host web\n    # hostkeeper:folder Work\n    # hostkeeper:note Main production server\n    HostName 203.0.113.7")
            para("Because they live in the config itself, they come along if you copy the file to another Mac. A folder with no hosts yet is remembered by HostKeeper on this Mac only.")
            subheading("Search")
            para("The filter box at the top of the sidebar matches host names, addresses, users, notes and tags. See Tags & Search.")
            subheading("Folders or tags?")
            para("A host lives in one folder but can have many tags. Use folders for where something belongs (Work, Home) and tags for what it is (prod, linux, raspberry-pi).")

        case .tags:
            heading("Tags & Search")
            para("Tags are short labels like prod, staging, linux or client-acme. Hosts and keys can have as many as you like, and each tag always shows in the same color.")
            subheading("Adding tags")
            step(1, "Open a host or key.")
            step(2, "In Tags, type a tag and press Return. Type several separated by commas, e.g. prod, web.")
            step(3, "Or pick one you've already used from the Existing menu.")
            para("Click the × on a tag to remove it. In Group by Tags view, you can also drag a host onto a tag to add that tag.")
            subheading("Searching")
            para("The filter box at the top of the sidebar searches hosts and keys. Words starting with # filter by tag. Everything has to match:")
            bullet("web", "Anything with “web” in its name, address, user, notes, folder or tags.")
            bullet("#prod", "Only things tagged prod.")
            bullet("#prod #linux", "Only things tagged both prod and linux.")
            bullet("#prod db", "Things tagged prod that also mention “db”.")
            para("The tag button in the toolbar lists every tag; tick tags to add them to the filter, or choose Clear Tag Filters.")
            subheading("Grouping")
            para("The Folders | Tags | All switch at the top of the sidebar changes how hosts are listed:")
            bullet("Folders", "One section per folder, plus Unfiled.")
            bullet("Tags", "One section per tag. A host with three tags appears in three sections. Hosts without tags are under Untagged.")
            bullet("All", "One flat list.")
            subheading("Renaming and removing tags")
            para("Right-click a tag section header (in Tags view), or a host ▸ Tags, to rename a tag everywhere, remove it from everything, or filter by it.")
            subheading("Where tags are saved")
            para("Host tags are saved in your config as a comment, which ssh ignores:")
            code("Host web\n    # hostkeeper:tags prod, linux\n    HostName 203.0.113.7")
            para("Key files can't hold comments, so HostKeeper remembers key tags itself, on this Mac.")

        case .keys:
            heading("SSH Keys")
            para("An SSH key is a pair of files. The private key (e.g. id_ed25519) stays on your Mac and proves who you are. The public key (the .pub file) goes on servers and sites like GitHub. Never share the private key.")
            para("The Keys section of the sidebar lists every key in ~/.ssh.")
            subheading("What you can do")
            bullet("Generate SSH Key…", "+ ▸ Generate SSH Key… creates a new pair. Ed25519 is the modern choice; use RSA only for very old servers. A passphrase protects the key if your Mac is stolen.")
            bullet("Import SSH Key…", "Copies a key you got elsewhere into ~/.ssh with safe permissions.")
            bullet("Copy Public Key", "Puts the .pub contents on the clipboard, ready to paste into GitHub, GitLab or a server.")
            bullet("Use with Host…", "Sets this key as a host's IdentityFile.")
            bullet("Add to Agent & Keychain", "Unlocks the key once and stores its passphrase in your macOS Keychain, so you're not asked again.")
            bullet("Change Passphrase…", "Opens Terminal to add, change or remove the passphrase.")
            bullet("Move to Trash…", "Moves both halves of the pair to the Trash, so you can still get them back.")
            subheading("The orange warning")
            para("ssh refuses private keys that other users on the Mac can read. If a key shows a warning triangle, click Fix Permissions.")
            subheading("Fingerprints")
            para("The fingerprint (SHA256:…) is a short ID for the key. GitHub and other services show the same value, so you can match which key is which.")

        case .connecting:
            heading("Connecting & Testing")
            bullet("Open in Terminal", "Opens a Terminal window and runs ssh for this host. If you have unsaved changes, it uses them.")
            bullet("Copy", "Copies the ssh command so you can paste it anywhere.")
            bullet("Test Connection", "Tries to log in with your keys only, with no password prompt, and runs nothing on the server. Green means key login works.")
            bullet("Install Public Key on Server…", "Runs ssh-copy-id, which asks for the server password once and then adds your public key so you can log in without a password after that. Save first, and make sure the host has an IdentityFile with a .pub next to it.")
            subheading("Reading test results")
            bullet("Logged in successfully", "Everything works.")
            bullet("Key login was refused", "The server is reachable but didn't accept your key, or the key needs a passphrase that isn't in the agent. Try Install Public Key, or Add to Agent & Keychain on the Keys page.")
            bullet("Host key verification failed", "You've never connected to this server, or its fingerprint changed. Connect once with Open in Terminal and answer yes if you trust it.")
            bullet("Could not resolve hostname", "Check the HostName for typos.")
            bullet("Connection timed out / refused", "The server is off, the port is wrong, or a firewall is blocking it.")

        case .saving:
            heading("Saving & Backups")
            para("Your changes stay in HostKeeper until you press ⌘S or click Save. The window title says “Edited” while there are unsaved changes, and you're asked before quitting with unsaved work.")
            subheading("Every save is checked first")
            para("Before writing, HostKeeper asks ssh itself to read the new config. If ssh finds a mistake, like a misspelled option or a missing value, nothing is saved and you see ssh's error message.")
            subheading("Your file is kept exactly as written")
            para("Comments, blank lines, spacing and lines you didn't touch are written back exactly as they were. View File shows exactly what will be saved.")
            subheading("Backups")
            para("Each save first copies the previous file to ~/.ssh/hostkeeper-backups. The 30 most recent are kept. Open Backups in the sidebar to preview any of them, or click Restore to load one. A restored version comes in as unsaved changes, so review it and press ⌘S to keep it, or Revert to Saved to cancel.")

        case .menuBar:
            heading("Menu Bar")
            para("The terminal icon in the menu bar lists your hosts, grouped by folder. Pick one to connect in Terminal right away.")
            para("While it's on, closing the HostKeeper window keeps the app running in the menu bar. Use Quit HostKeeper in that menu, or ⌘Q, to quit fully.")
            para("Turn the icon on or off in HostKeeper ▸ Settings (⌘,).")

        case .updates:
            heading("Updates")
            para("HostKeeper checks for a new version once a day. When one is available, it shows what's new and asks before installing anything.")
            step(1, "Click Install Update.")
            step(2, "When the download finishes, click Install and Relaunch. HostKeeper restarts on the new version.")
            para("Your hosts, folders, tags, notes, keys and backups are all kept. They live in ~/.ssh and your settings, not inside the app.")
            subheading("Checking now")
            para("Choose HostKeeper ▸ Check for Updates…, or use the same item in the menu bar icon.")
            subheading("Turning automatic checks off")
            para("Open HostKeeper ▸ Settings (⌘,) and turn off Automatically check for updates. You can still check by hand.")
            subheading("Is it safe?")
            para("Every update is signed by the HostKeeper project. HostKeeper checks that signature and refuses anything that doesn't match, so a tampered download can't be installed.")
            subheading("Homebrew")
            para("If you installed with Homebrew, updates work the same way, and brew upgrade --cask hostkeeper also works.")
            subheading("Development builds")
            para("Builds run from Xcode or swift run don't check for updates; Check for Updates… is greyed out there.")

        case .options:
            EmptyView()

        case .troubleshooting:
            heading("Troubleshooting")
            bullet("“ssh rejected the new config”", "A setting has a typo or an empty value. The message names the line. Fix it, or remove it in Other options, and save again.")
            bullet("“Too many authentication failures”", "Your agent offers too many keys. Set Only use the identity file above to Yes for that host.")
            bullet("“Permission denied (publickey)”", "The server doesn't have your public key. Use Install Public Key on Server…, or paste Copy Public Key into the server's ~/.ssh/authorized_keys.")
            bullet("“UNPROTECTED PRIVATE KEY FILE”", "Open the key under Keys and click Fix Permissions.")
            bullet("A host does something unexpected", "An earlier block, often Host *, may already set that option; ssh uses the first value it finds. Move specific hosts above general ones.")
            bullet("Something went wrong after saving", "Open Backups and restore the version from before.")
            subheading("Check from Terminal")
            para("This shows every setting ssh will actually use for a host:")
            code("ssh -G web")
        case .shortcuts:
            heading("Keyboard Shortcuts")
            shortcut("⌘N", "New host")
            shortcut("⌘S", "Save")
            shortcut("⌘,", "Settings")
            shortcut("⌘?", "HostKeeper Help")
            shortcut("⌘F", "Filter hosts and keys (type #tag to filter by tag)")
            shortcut("⌘Q", "Quit")
        }
    }

    // MARK: Building blocks

    private func heading(_ s: String) -> some View {
        Text(s).font(.largeTitle.bold()).padding(.bottom, 4)
    }

    private func subheading(_ s: String) -> some View {
        Text(s).font(.title3.bold()).padding(.top, 8)
    }

    private func para(_ s: String) -> some View {
        Text(s).fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ title: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).bold()
            Text(s).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ n: Int, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").bold().monospacedDigit()
            Text(s).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func code(_ s: String) -> some View {
        Text(s)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 6))
    }

    private func shortcut(_ keys: String, _ s: String) -> some View {
        HStack {
            Text(keys).font(.system(.body, design: .monospaced)).frame(width: 60, alignment: .leading)
            Text(s)
        }
    }
}

private struct OptionReferenceView: View {
    @Binding var search: String

    private var matches: [OptionInfo] {
        guard !search.isEmpty else { return OptionReference.all }
        return OptionReference.all.filter {
            $0.key.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            Text("What each ssh setting does. You can add any of them to a host under Other options. The full technical list is in Terminal: man ssh_config")
                .foregroundStyle(.secondary)
            ForEach(OptionInfo.Category.allCases, id: \.self) { category in
                let items = matches.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.rawValue) {
                        ForEach(items) { option in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.key).font(.system(.headline, design: .monospaced))
                                Text(option.summary).fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Text(option.example)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Button("Copy") { Shell.copy(option.example) }
                                        .buttonStyle(.borderless).font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            if matches.isEmpty {
                Text("No option matches “\(search)”.").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search, prompt: "Search options")
    }
}
