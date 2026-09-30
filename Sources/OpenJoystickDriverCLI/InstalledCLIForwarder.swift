import Darwin
import Foundation

package enum InstalledCLIForwarder {
  enum Resolution: Equatable {
    case local
    case forward(URL)
    case staleInstallation(URL)
  }

  static let installedExecutableURL = URL(
    fileURLWithPath: "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  )

  static func resolve(
    currentExecutableURL: URL,
    mainBundleURL: URL,
    installedExecutableURL: URL = installedExecutableURL,
    repositoryCLIOverride: Bool = ProcessInfo.processInfo.environment["OJD_RUN_REPOSITORY_CLI"]
      == "1",
    isExecutableFile: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
    installedCLIIsCurrent: (URL, URL) -> Bool = installedCLIIsCurrent(
      sourceExecutableURL:
      installedExecutableURL:
    )
  ) -> Resolution {
    guard mainBundleURL.pathExtension != "app", !repositoryCLIOverride else { return .local }
    let current = currentExecutableURL.resolvingSymlinksInPath().standardizedFileURL
    let installed = installedExecutableURL.resolvingSymlinksInPath().standardizedFileURL
    guard current != installed, isExecutableFile(installed.path) else { return .local }
    guard installedCLIIsCurrent(current, installed) else { return .staleInstallation(installed) }
    return .forward(installed)
  }

  package static func forwardIfNeeded(
    arguments: [String],
    currentExecutableURL: URL = Bundle.main.executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments[0]),
    mainBundleURL: URL = Bundle.main.bundleURL
  ) {
    let executable: URL
    switch resolve(currentExecutableURL: currentExecutableURL, mainBundleURL: mainBundleURL) {
    case .local: return
    case .forward(let target): executable = target
    case .staleInstallation:
      fputs(
        "ojd: The installed OpenJoystickDriver.app is older than these repository sources. "
          + "Run './Scripts/ojd build install-fast dev', "
          + "or set OJD_RUN_REPOSITORY_CLI=1 to run this build.\n",
        stderr
      )
      exit(1)
    }

    let strings = ["ojd"] + arguments
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { string in
      string.withCString { strdup($0) }
    }
    guard pointers.allSatisfy({ $0 != nil }) else {
      release(pointers)
      fputs("ojd: Could not allocate arguments for the installed ojd. Retry the command.\n", stderr)
      exit(127)
    }
    pointers.append(nil)
    defer { release(pointers) }

    let result = executable.path.withCString { path in
      pointers.withUnsafeMutableBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else { return Int32(-1) }
        return execv(path, baseAddress)
      }
    }
    guard result == -1 else { return }
    let message = String(cString: strerror(errno))
    fputs(
      "ojd: Could not run the installed ojd: \(message). Reinstall OpenJoystickDriver.app.\n",
      stderr
    )
    exit(127)
  }

  private static func release(_ pointers: [UnsafeMutablePointer<CChar>?]) {
    for pointer in pointers { if let pointer { free(UnsafeMutableRawPointer(pointer)) } }
  }

  private static func installedCLIIsCurrent(
    sourceExecutableURL: URL,
    installedExecutableURL: URL
  ) -> Bool {
    guard let repositoryRoot = repositoryRoot(containing: sourceExecutableURL) else { return true }
    guard
      let installedDate = try? installedExecutableURL.resourceValues(forKeys: [
        .contentModificationDateKey
      ]).contentModificationDate
    else { return false }

    let packageManifest = repositoryRoot.appendingPathComponent("Package.swift")
    guard fileIsNotNewer(packageManifest, than: installedDate) else { return false }
    let sources = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
    guard
      let enumerator = FileManager.default.enumerator(
        at: sources,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
      )
    else { return false }
    for case let file as URL in enumerator {
      guard
        let values = try? file.resourceValues(forKeys: [
          .contentModificationDateKey, .isRegularFileKey,
        ])
      else { return false }
      if values.isRegularFile == true, let date = values.contentModificationDate,
        date > installedDate
      {
        return false
      }
    }
    return true
  }

  private static func fileIsNotNewer(_ file: URL, than date: Date) -> Bool {
    guard
      let modificationDate = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
    else { return false }
    return modificationDate <= date
  }

  private static func repositoryRoot(containing executableURL: URL) -> URL? {
    var directory = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
    while directory.path != "/" {
      let packageManifest = directory.appendingPathComponent("Package.swift")
      let applicationSources = directory.appendingPathComponent("Sources/OpenJoystickDriver")
      if FileManager.default.fileExists(atPath: packageManifest.path),
        FileManager.default.fileExists(atPath: applicationSources.path)
      {
        return directory
      }
      directory.deleteLastPathComponent()
    }
    return nil
  }
}
