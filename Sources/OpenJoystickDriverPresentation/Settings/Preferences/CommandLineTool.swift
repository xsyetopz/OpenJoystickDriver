#if canImport(AppKit) && canImport(SwiftUI)

  import Combine
  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The `/usr/local/bin/ojd` link that lets Terminal run the app executable as the `ojd` command.
  ///
  /// The executable acts as the command line when it runs under the name `ojd`, and the link keeps
  /// the app's code signature, so the service accepts the command line as a client.
  struct CommandLineToolLink: Sendable {
    /// Why installing or removing the link failed.
    enum Failure: LocalizedError, Equatable {
      /// The user cancelled the administrator password prompt.
      case cancelled
      /// A file that is not a link is at the link path; the value is the path.
      case blockedByFile(String)
      /// The administrator command failed; the value is the error text.
      case failed(String)

      /// The message for the failure: the cancelled prompt, the path of the blocking file or the
      /// error text.
      var errorDescription: String? {
        switch self {
        case .cancelled:
          return OJDLocalized.string("ui.settings.commandLine.toolCancelled")
        case .blockedByFile(let path):
          return OJDLocalized.formatted(
            "ui.settings.commandLine.toolBlocked",
            path
          )
        case .failed(let detail): return detail
        }
      }
    }

    /// The path of the link: `/usr/local/bin/ojd`.
    static let defaultLinkPath = CommandLineToolLinkStatus.defaultPath

    /// Where the link is.
    let linkURL: URL
    /// The app executable that the link points to.
    let executableURL: URL
    /// Runs a shell command with administrator rights after macOS asks for a password.
    let runAsAdministrator: @Sendable (String) throws -> Void

    /// The link at the default path, to the running app executable, created with the administrator
    /// password prompt.
    static let system = Self(
      linkURL: URL(fileURLWithPath: defaultLinkPath),
      executableURL: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]),
      runAsAdministrator: AdministratorShell.run
    )

    /// What is at the link path, classified by `CommandLineToolLinkStatus` as `ojd status` does.
    var status: CommandLineToolLinkStatus {
      .probe(path: linkURL.path, executable: executableURL)
    }

    /// Creates the link, with the administrator password prompt when the folder or the link needs
    /// it.
    ///
    /// A link that points elsewhere is replaced.
    ///
    /// - Throws: ``Failure/blockedByFile(_:)`` when a file that is not a link is at the link path;
    ///   ``Failure/cancelled`` when the user cancels the password prompt; ``Failure/failed(_:)``
    ///   when the administrator command fails; the file manager's error for any other failure.
    func install() throws {
      if status.state == .blockedByFile { throw Failure.blockedByFile(linkURL.path) }
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

    /// Removes the link, with the administrator password prompt when it needs it; a file that is
    /// not a link is left alone.
    ///
    /// - Throws: ``Failure/cancelled`` when the user cancels the password prompt;
    ///   ``Failure/failed(_:)`` when the administrator command fails; the file manager's error for
    ///   any other failure.
    func uninstall() throws {
      guard (try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)) != nil else {
        return
      }
      do { try FileManager.default.removeItem(at: linkURL) } catch
        where Self.needsAdministrator(error)
      { try runAsAdministrator("/bin/rm -f \(Self.quoted(linkURL.path))") }
    }

    /// Returns whether the error says that the change needs administrator rights.
    private static func needsAdministrator(_ error: any Error) -> Bool {
      let nsError = error as NSError
      if nsError.domain == NSCocoaErrorDomain {
        return nsError.code == NSFileWriteNoPermissionError
      }
      return nsError.domain == NSPOSIXErrorDomain
        && (nsError.code == Int(EACCES) || nsError.code == Int(EPERM))
    }

    /// Quotes `text` as one POSIX shell word.
    static func quoted(_ text: String) -> String {
      "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
  }

  /// Runs shell commands through the macOS administrator password prompt.
  enum AdministratorShell {
    /// The error number that AppleScript reports when the user cancels the password prompt.
    private static let userCancelled = -128

    /// Runs `command` as a shell command with administrator rights.
    ///
    /// - Throws: ``CommandLineToolLink/Failure/cancelled`` when the user cancels the password
    ///   prompt; ``CommandLineToolLink/Failure/failed(_:)`` with the error text for any other
    ///   failure.
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
      unsafe script?.executeAndReturnError(&error)
      guard let error else { return }
      if error[NSAppleScript.errorNumber] as? Int == userCancelled {
        throw CommandLineToolLink.Failure.cancelled
      }
      throw CommandLineToolLink.Failure.failed(
        error[NSAppleScript.errorMessage] as? String
          ?? OJDLocalized.string(
            "platform.macos.ui.settings.commandLine.toolFailed"
          )
      )
    }
  }

  /// The state of the `ojd` link for Settings > Advanced, with its Install and Uninstall actions.
  @MainActor
  final class CommandLineToolModel: ObservableObject {
    /// What is at the link path.
    @Published
    private(set) var status: CommandLineToolLinkStatus
    /// The text of the last failed install or uninstall; a cancelled password prompt sets none.
    @Published
    private(set) var errorMessage: String?

    /// The link to install and remove.
    let link: CommandLineToolLink

    /// Creates the model and reads the status of the link.
    init(link: CommandLineToolLink = .system) {
      self.link = link
      self.status = link.status
    }

    /// Reads the status of the link again.
    func refresh() { status = link.status }

    /// Installs the link and reads the status; a failure shows in ``errorMessage``.
    func install() { perform(link.install) }

    /// Removes the link and reads the status; a failure shows in ``errorMessage``.
    func uninstall() { perform(link.uninstall) }

    /// Clears the error, runs `change`, and reads the status.
    ///
    /// A failure shows in ``errorMessage``, unless the user cancelled the password prompt.
    private func perform(_ change: () throws -> Void) {
      errorMessage = nil
      do { try change() } catch CommandLineToolLink.Failure.cancelled {} catch {
        errorMessage = error.localizedDescription
      }
      refresh()
    }
  }

#endif
