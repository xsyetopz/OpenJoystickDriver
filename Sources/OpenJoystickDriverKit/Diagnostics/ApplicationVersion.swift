import Foundation

/// The version of the running OJD build.
package enum ApplicationVersion {
  /// The release version without build metadata, such as `0.5.0`.
  package static var current: String { buildIdentity.semanticVersion }

  /// The identity of the build, read from the app bundle.
  package static var buildIdentity: BuildIdentity { .current() }

  /// The release version with build metadata, for display and reports.
  package static var display: String { buildIdentity.display }
}
