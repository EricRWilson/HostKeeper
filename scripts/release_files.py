#!/usr/bin/env python3
"""Writes the files a release publishes besides the app itself.

  build/appcast.xml      Sparkle update feed, attached to the GitHub release. Installed copies
                         read it from releases/latest/download/appcast.xml.
  Casks/hostkeeper.rb    Homebrew cask, committed to main so `brew upgrade` sees the new version.

Usage: scripts/release_files.py VERSION BUILD ZIP 'sparkle:edSignature="…" length="…"'
"""
import hashlib
import html
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = "EricRWilson/HostKeeper"


def changelog_section(version: str) -> list[str]:
    lines, found = [], False
    for line in Path("CHANGELOG.md").read_text().splitlines():
        if line.strip() == f"## {version}":
            found = True
            continue
        if found and line.startswith("## "):
            break
        if found:
            lines.append(line)
    if not any(l.strip() for l in lines):
        sys.exit(f"CHANGELOG.md has no notes under '## {version}'. Add them before releasing.")
    return lines


def notes_html(lines: list[str]) -> str:
    """Just enough Markdown for changelog entries: paragraphs, bullet lists and `code`."""
    def inline(text: str) -> str:
        text = html.escape(text)
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)

    out, in_list = [], False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(stripped[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if stripped:
            out.append(f"<p>{inline(stripped)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def appcast(version: str, build: str, signature_attrs: str, notes: str) -> str:
    url = f"https://github.com/{REPO}/releases/download/v{version}/HostKeeper-{version}.zip"
    date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>HostKeeper</title>
    <link>https://github.com/{REPO}</link>
    <item>
      <title>Version {version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
{notes}
      ]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature_attrs} />
    </item>
  </channel>
</rss>
"""


def cask(version: str, sha256: str) -> str:
    return f'''cask "hostkeeper" do
  version "{version}"
  sha256 "{sha256}"

  url "https://github.com/{REPO}/releases/download/v#{{version}}/HostKeeper-#{{version}}.zip"
  name "HostKeeper"
  desc "Free, open-source editor for your SSH config and SSH keys"
  homepage "https://github.com/{REPO}"

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
'''


def main() -> None:
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    version, build, zip_path, signature_attrs = sys.argv[1:]
    if not re.fullmatch(r'sparkle:edSignature="[^"]+" length="\d+"', signature_attrs.strip()):
        sys.exit(f"Unexpected sign_update output: {signature_attrs!r}")

    notes = notes_html(changelog_section(version))
    Path("build").mkdir(exist_ok=True)
    Path("build/appcast.xml").write_text(appcast(version, build, signature_attrs.strip(), notes))

    sha256 = hashlib.sha256(Path(zip_path).read_bytes()).hexdigest()
    Path("Casks").mkdir(exist_ok=True)
    Path("Casks/hostkeeper.rb").write_text(cask(version, sha256))
    print(f"Wrote build/appcast.xml and Casks/hostkeeper.rb for {version} (build {build})")


if __name__ == "__main__":
    main()
