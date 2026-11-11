import Foundation

/// The single source of the version number. build-app.sh reads these two lines into Info.plist,
/// so bump them here when you release a new build.
enum AppVersion {
    static let version = "1.4.2"
    static let build = "7"

    /// The build number is only for the updater, so it isn't shown to people.
    static var display: String { "Version \(version)" }
}
