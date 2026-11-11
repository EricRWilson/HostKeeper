cask "hostkeeper" do
  version "1.4.1"
  sha256 "c1b44f2c053a1f2a8fe5cf259a6d02f1d27554391c462361743ff8aeb328f813"

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
