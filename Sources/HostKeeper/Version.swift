import Foundation

/// The single source of the version number. build-app.sh reads these two lines into Info.plist,
/// so bump them here when you release a new build.
enum AppVersion {
    static let version = "1.3.0"
    static let build = "4"

    static var display: String { "Version \(version) (\(build))" }
}
