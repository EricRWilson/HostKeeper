import Foundation
import Observation
import Sparkle
import SwiftUI

/// Wraps Sparkle, which checks the update feed published with each GitHub release,
/// shows what's new, and installs the update in place.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    /// Updates only work in the packaged app; Xcode and `swift run` builds have no feed or bundle to replace.
    var isAvailable: Bool { controller != nil }

    var automaticallyChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    private init() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        // Sparkle changes this property on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @Bindable private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
            .help(updater.isAvailable ? "" : "Updates are available in the installed app, not in development builds")
    }
}
