import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct CommandLineToolTests {
  private struct Sandbox {
    let root: URL
    let executable: URL
    let link: URL
    let adminCommands = Locked<[String]>([])

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "CommandLineToolTests.\(UUID().uuidString)"
      )
      executable = root.appendingPathComponent("App/OpenJoystickDriver")
      link = root.appendingPathComponent("bin/ojd")
      try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data().write(to: executable)
    }

    func tool(adminResult: CommandLineToolLink.Failure? = nil) -> CommandLineToolLink {
      let commands = adminCommands
      return CommandLineToolLink(linkURL: link, executableURL: executable) { command in
        commands.withLock { $0.append(command) }
        if let adminResult { throw adminResult }
      }
    }

    func remove() {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: link.deletingLastPathComponent().path
      )
      try? FileManager.default.removeItem(at: root)
    }
  }

  @Test
  func installLinksExecutableAndUninstallRemovesIt() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let tool = sandbox.tool()
    #expect(tool.status.state == .missing)

    try tool.install()
    #expect(tool.status.state == .installed)
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: sandbox.link.path)
        == sandbox.executable.path
    )

    try tool.uninstall()
    #expect(tool.status.state == .missing)
    #expect(sandbox.adminCommands.withLock { $0 }.isEmpty)
  }

  @Test
  func installReplacesLinkToAnotherCopy() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try FileManager.default.createDirectory(
      at: sandbox.link.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let other = sandbox.root.appendingPathComponent("Old/OpenJoystickDriver")
    try FileManager.default.createDirectory(
      at: other.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data().write(to: other)
    try FileManager.default.createSymbolicLink(
      atPath: sandbox.link.path,
      withDestinationPath: other.path
    )
    let tool = sandbox.tool()
    #expect(tool.status.state == .linkedElsewhere)
    #expect(tool.status.target == other.path)

    try tool.install()
    #expect(tool.status.state == .installed)
  }

  @Test
  func installReplacesBrokenLink() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try FileManager.default.createDirectory(
      at: sandbox.link.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      atPath: sandbox.link.path,
      withDestinationPath: "/Applications/Old.app/Contents/MacOS/OpenJoystickDriver"
    )
    let tool = sandbox.tool()
    #expect(tool.status.state == .broken)

    try tool.install()
    #expect(tool.status.state == .installed)
  }

  @Test
  func relativeLinkToExecutableIsInstalled() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try FileManager.default.createDirectory(
      at: sandbox.link.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      atPath: sandbox.link.path,
      withDestinationPath: "../App/OpenJoystickDriver"
    )

    #expect(sandbox.tool().status.state == .installed)
  }

  @Test
  func regularFileIsNeverReplacedOrRemoved() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try FileManager.default.createDirectory(
      at: sandbox.link.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("keep".utf8).write(to: sandbox.link)
    let tool = sandbox.tool()
    #expect(tool.status.state == .blockedByFile)

    #expect(throws: CommandLineToolLink.Failure.blockedByFile(sandbox.link.path)) {
      try tool.install()
    }
    try tool.uninstall()
    #expect(try Data(contentsOf: sandbox.link) == Data("keep".utf8))
    #expect(sandbox.adminCommands.withLock { $0 }.isEmpty)
  }

  @Test
  func protectedFolderFallsBackToAdministratorPrompt() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let folder = sandbox.link.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

    try sandbox.tool().install()

    #expect(
      sandbox.adminCommands.withLock { $0 } == [
        "/bin/mkdir -p '\(folder.path)' && /bin/ln -sfn '\(sandbox.executable.path)' "
          + "'\(sandbox.link.path)'"
      ]
    )
  }

  @Test
  @MainActor
  func cancellingPasswordPromptShowsNoError() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let folder = sandbox.link.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

    let cancelled = CommandLineToolModel(link: sandbox.tool(adminResult: .cancelled))
    cancelled.install()
    #expect(cancelled.errorMessage == nil)
    #expect(cancelled.status.state == .missing)

    let failed = CommandLineToolModel(link: sandbox.tool(adminResult: .failed("denied")))
    failed.install()
    #expect(failed.errorMessage == "denied")
  }

  @Test
  func quotingKeepsPathOneShellWord() {
    #expect(CommandLineToolLink.quoted("/Users/o'neil/ojd") == "'/Users/o'\\''neil/ojd'")
  }
}
