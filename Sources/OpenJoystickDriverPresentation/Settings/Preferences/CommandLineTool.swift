#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The `/usr/local/bin/ojd` link that lets Terminal run the app executable as the `ojd` command.
  ///
  /// The executable acts as the command line when it runs under the name `ojd`, and the link keeps
  /// the app's code signature, so the service accepts the command line as a client.
  struct CommandLineToolLink: Sendable {
    enum State: Equatable {
      case notInstalled
      case installed
      /// A link to something else, such as another copy of the app; installing replaces it.
      case linkedElsewhere(String)
      /// A file that is not a link; the app never replaces it.
      case blockedByFile
    }

    enum Failure: LocalizedError, Equatable {
      case cancelled
      case blockedByFile(String)
      case failed(String)

      var errorDescription: String? {
        switch self {
        case .cancelled:
          return OJDLocalized.string("settings.commandLineTool.cancelled", fallback: "Cancelled.")
        case .blockedByFile(let path):
          return OJDLocalized.formatted(
            "settings.commandLineTool.blocked",
            fallback: "%@ is a file, not a link. Remove it, then install again.",
            path
          )
        case .failed(let detail): return detail
        }
      }
    }

    static let defaultLinkPath = "/usr/local/bin/ojd"

    let linkURL: URL
    let executableURL: URL
    /// Runs a shell command with administrator rights after macOS asks for a password.
    let runAsAdministrator: @Sendable (String) throws -> Void

    static let system = Self(
      linkURL: URL(fileURLWithPath: defaultLinkPath),
      executableURL: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]),
      runAsAdministrator: AdministratorShell.run
    )

    var state: State {
      let fileManager = FileManager.default
      guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path)
      else { return fileManager.fileExists(atPath: linkURL.path) ? .blockedByFile : .notInstalled }
      let target = URL(
        fileURLWithPath: destination,
        relativeTo: linkURL.deletingLastPathComponent()
      )
      return target.resolvingSymlinksInPath().path == executableURL.resolvingSymlinksInPath().path
        ? .installed : .linkedElsewhere(destination)
    }

    func install() throws {
      if state == .blockedByFile { throw Failure.blockedByFile(linkURL.path) }
      let fileManager = FileManager.default
      let folder = linkURL.deletingLastPathComponent()
      do {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if (try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path)) != nil {
          try fileManager.removeItem(at: linkURL)
        }
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: executableURL)
      } catch  where Self.needsAdministrator(error) {
        try runAsAdministrator(
          "/bin/mkdir -p \(Self.quoted(folder.path)) && /bin/ln -sfn "
            + "\(Self.quoted(executableURL.path)) \(Self.quoted(linkURL.path))"
        )
      }
    }

    /// Removes the link; a file that is not a link is left alone.
    func uninstall() throws {
      guard (try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)) != nil else {
        return
      }
      do { try FileManager.default.removeItem(at: linkURL) } catch
        where Self.needsAdministrator(error)
      { try runAsAdministrator("/bin/rm -f \(Self.quoted(linkURL.path))") }
    }

    private static func needsAdministrator(_ error: any Error) -> Bool {
      let error = error as NSError
      if error.domain == NSCocoaErrorDomain { return error.code == NSFileWriteNoPermissionError }
      return error.domain == NSPOSIXErrorDomain
        && (error.code == Int(EACCES) || error.code == Int(EPERM))
    }

    /// Quotes `text` as one POSIX shell word.
    static func quoted(_ text: String) -> String {
      "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
  }

  /// Runs shell commands through the macOS administrator password prompt.
  enum AdministratorShell {
    private static let userCancelled = -128

    static func run(_ command: String) throws {
      let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"",
        with: "\\\""
      )
      let script = NSAppleScript(
        source: "do shell script \"\(literal)\" with administrator privileges"
      )
      // `executeAndReturnError` reports through an `NSDictionary`.
      // swiftlint:disable:next legacy_objc_type
      var error: NSDictionary?
      script?.executeAndReturnError(&error)
      guard let error else { return }
      if error[NSAppleScript.errorNumber] as? Int == userCancelled {
        throw CommandLineToolLink.Failure.cancelled
      }
      throw CommandLineToolLink.Failure.failed(
        error[NSAppleScript.errorMessage] as? String
          ?? OJDLocalized.string(
            "settings.commandLineTool.failed",
            fallback: "macOS did not allow the change."
          )
      )
    }
  }

  @MainActor
  final class CommandLineToolModel: ObservableObject {
    @Published
    private(set) var state: CommandLineToolLink.State
    @Published
    private(set) var errorMessage: String?

    let link: CommandLineToolLink

    init(link: CommandLineToolLink = .system) {
      self.link = link
      self.state = link.state
    }

    func refresh() { state = link.state }

    func install() { perform(link.install) }

    func uninstall() { perform(link.uninstall) }

    private func perform(_ change: () throws -> Void) {
      errorMessage = nil
      do { try change() } catch CommandLineToolLink.Failure.cancelled {} catch {
        errorMessage = error.localizedDescription
      }
      refresh()
    }
  }

#endif
