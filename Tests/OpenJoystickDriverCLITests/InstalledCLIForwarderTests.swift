import Foundation
import Testing

@testable import OpenJoystickDriverCLI

struct InstalledCLIForwarderTests {
  private let sourceExecutable = URL(fileURLWithPath: "/repo/.build/debug/OpenJoystickDriver")
  private let sourceBundle = URL(fileURLWithPath: "/repo/.build/debug")
  private let installedExecutable = URL(
    fileURLWithPath: "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  )

  @Test
  func sourceBuildCLIUsesInstalledSignedExecutable() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      installedExecutableURL: installedExecutable,
      isExecutableFile: { $0 == self.installedExecutable.path },
      installedCLIIsCurrent: { _, _ in true }
    )

    #expect(resolution == .forward(installedExecutable))
  }

  @Test
  func applicationBundleExecutesItsOwnCLI() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: installedExecutable,
      mainBundleURL: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app"),
      installedExecutableURL: installedExecutable
    ) { _ in true }

    #expect(resolution == .local)
  }

  @Test
  func sourceBuildRunsLocallyWhenNoInstalledCLIExists() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      installedExecutableURL: installedExecutable
    ) { _ in false }

    #expect(resolution == .local)
  }

  @Test
  func symlinkToInstalledExecutableDoesNotForwardRecursively() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("OpenJoystickDriver")
    let symlink = directory.appendingPathComponent("ojd")
    #expect(FileManager.default.createFile(atPath: executable.path, contents: Data()))
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: executable)

    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: symlink,
      mainBundleURL: sourceBundle,
      installedExecutableURL: executable
    ) { _ in true }

    #expect(resolution == .local)
  }

  @Test
  func staleInstalledCLIIsRejectedBeforeForwarding() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      installedExecutableURL: installedExecutable,
      isExecutableFile: { _ in true },
      installedCLIIsCurrent: { _, _ in false }
    )

    #expect(resolution == .staleInstallation(installedExecutable))
  }

  @Test
  func explicitRepositoryOverrideSkipsInstalledCLI() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      installedExecutableURL: installedExecutable,
      repositoryCLIOverride: true,
      isExecutableFile: { _ in true },
      installedCLIIsCurrent: { _, _ in true }
    )

    #expect(resolution == .local)
  }

}
