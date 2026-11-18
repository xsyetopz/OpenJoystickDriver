#if canImport(AppKit)

  import AppKit

  extension ProfileAppChoices {
    /// The name of the installed app `bundleID`, or the identifier when no installed app has it.
    static func appName(for bundleID: String) -> String {
      entry(for: bundleID) {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0).flatMap(choice(forAppAt:))
      }.title
    }
  }

#endif
