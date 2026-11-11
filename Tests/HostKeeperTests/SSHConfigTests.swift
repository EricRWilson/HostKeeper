import Foundation
import Testing
@testable import SSHConfigKit

private let sample = """
# Global settings
Include ~/.orbstack/ssh/config
AddKeysToAgent yes

Host web prod-web
  HostName 10.0.0.5
  User deploy
  Port=2222
  # jump through bastion
  ProxyJump bastion

Host *.internal
\tIdentityFile "~/.ssh/my key"

Match host foo exec "test -f /tmp/x"
  ForwardAgent no

"""

@Test func roundTripIsByteForByte() {
    #expect(SSHConfig.parse(sample).render() == sample)
}

@Test func roundTripsRealConfigIfPresent() throws {
    let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/config")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    #expect(SSHConfig.parse(text).render() == text)
}

@Test func parsesBlocks() {
    let config = SSHConfig.parse(sample)
    #expect(config.blocks.map(\.kind) == [.global, .host, .host, .match])
    let web = config.blocks[1]
    #expect(web.pattern == "web prod-web")
    #expect(web.value("hostname") == "10.0.0.5")
    #expect(web.value("Port") == "2222")
    #expect(web.connectAlias == "web")
    #expect(config.blocks[2].connectAlias == nil)
    #expect(config.blocks[2].value("IdentityFile") == "~/.ssh/my key")
}

@Test func editingOnlyTouchesChangedLines() {
    var config = SSHConfig.parse(sample)
    config.blocks[1].set("User", "root")
    config.blocks[1].set("ProxyJump", "")
    config.blocks[1].set("ForwardAgent", "yes")
    let out = config.render()
    #expect(out.contains("  User root\n"))
    #expect(!out.contains("ProxyJump"))
    #expect(out.contains("  ForwardAgent yes\n"))
    #expect(out.contains("  Port=2222\n"))
    #expect(out.contains("  # jump through bastion\n"))
}

@Test func newHostRendersWithIndentAndQuotes() {
    var config = SSHConfig.parse("")
    var host = HostBlock.newHost("box")
    host.set("HostName", "box.local")
    host.set("IdentityFile", "~/.ssh/a b")
    config.blocks.append(host)
    #expect(config.render() == "Host box\n    HostName box.local\n    IdentityFile \"~/.ssh/a b\"\n")
}

@Test func folderAndNoteAreStoredAsComments() {
    var config = SSHConfig.parse(sample)
    config.blocks[1].folder = "Work"
    config.blocks[1].note = "prod box"
    var reparsed = SSHConfig.parse(config.render())
    #expect(reparsed.blocks[1].folder == "Work")
    #expect(reparsed.blocks[1].note == "prod box")
    #expect(config.render().contains("Host web prod-web\n  # hostkeeper:note prod box\n  # hostkeeper:folder Work\n"))
    reparsed.blocks[1].folder = "Home Lab"
    #expect(reparsed.blocks[1].folder == "Home Lab")
    reparsed.blocks[1].folder = ""
    reparsed.blocks[1].note = ""
    #expect(reparsed.render() == sample)
}

@Test func tagsAreStoredAsCommentsAndNormalized() {
    var config = SSHConfig.parse(sample)
    config.blocks[1].tags = ["prod", " web ", "Prod", "", "a,b"]
    #expect(config.blocks[1].tags == ["prod", "web", "a b"])
    #expect(config.render().contains("  # hostkeeper:tags prod, web, a b\n"))
    let reparsed = SSHConfig.parse(config.render())
    #expect(reparsed.blocks[1].tags == ["prod", "web", "a b"])
    #expect(reparsed.blocks[1].hasTag("PROD"))
    config.blocks[1].tags = []
    #expect(config.render() == sample)
}
