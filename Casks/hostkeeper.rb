cask "hostkeeper" do
  version "1.3.0"
  sha256 "a661767eedfe0d40f338f9790937bac7329df5567bd7fb91b145be44df159ead"

  url "https://github.com/EricRWilson/HostKeeper/releases/download/v#{version}/HostKeeper-#{version}.zip"
  name "HostKeeper"
  desc "Free, open-source editor for your SSH config and SSH keys"
  homepage "https://github.com/EricRWilson/HostKeeper"

  # HostKeeper updates itself with Sparkle; brew upgrade works too.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "HostKeeper.app"

  # Removes only HostKeeper's own settings and caches. Your ~/.ssh config, keys and backups are never touched.
  zap trash: [
    "~/Library/Application Support/HostKeeper-Dev",
    "~/Library/Caches/io.github.ericrwilson.hostkeeper",
    "~/Library/HTTPStorages/io.github.ericrwilson.hostkeeper",
    "~/Library/Preferences/io.github.ericrwilson.hostkeeper.plist",
  ]

  caveats <<~EOS
    HostKeeper isn't signed with a paid Apple Developer ID, so macOS blocks it the first time.
    Open it once, click Done, then go to System Settings → Privacy & Security and click Open Anyway.
  EOS
end
