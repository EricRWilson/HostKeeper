import Foundation

/// The single source of the version number. build-app.sh reads these two lines into Info.plist,
/// so bump them here when you release a new build.
enum AppVersion {
    static let version = "1.4.1"
    static let build = "6"

    static var display: String { "Version \(version) (\(build))" }
}
