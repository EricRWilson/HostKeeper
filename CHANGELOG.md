# Changelog

Add new entries under **Unreleased** as you work. When releasing, rename it to the new version number.

## Unreleased

- Releases now include SHA-256 checksums and a GitHub build attestation, so you can confirm a download is exactly what was built from this repository. See **Verify your download** in the README.

## 1.4.0

- **Automatic updates:** HostKeeper checks for new versions once a day, shows what's new, and installs updates for you. Choose **HostKeeper → Check for Updates…** to check now, or turn automatic checks off in Settings.
- **Homebrew:** install with `brew install --cask hostkeeper` after adding the tap (see the README), and update with `brew upgrade`.
- The app icon now shows in the Dock when running a development build from Xcode.
- If you have 1.3.0, download 1.4.0 once by hand. After that, updates arrive automatically.

## 1.3.0

First public release.

- New app icon.
- Runs natively on both Apple Silicon and Intel Macs.
- Downloads as a DMG or ZIP from GitHub Releases.
- Development builds use a practice config, so working on HostKeeper never touches your real `~/.ssh`.

## 1.2.0

- Tags for hosts and keys, with colors.
- Search by tag with `#tag`, plus a tag filter menu in the toolbar.
- Group the sidebar by Folders, Tags, or show All.
- Rename or remove a tag everywhere at once.

## 1.1.0

- Built-in Help with a guide to every feature.
- Plain-language reference for 37 ssh options, shown as tooltips on the host page.
- Version number in About, Settings and the sidebar.

## 1.0.0

- Edit hosts in `~/.ssh/config` while keeping comments and formatting exactly.
- Folders and notes.
- SSH key management: generate, import, copy public keys, add to Keychain, fix permissions.
- Test Connection and Install Public Key on Server.
- Every change is checked by ssh before saving, and each save keeps a backup.
- Menu bar quick-connect.
