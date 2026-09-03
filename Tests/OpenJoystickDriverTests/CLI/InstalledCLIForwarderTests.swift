import Foundation
import Testing

@testable import OpenJoystickDriver

struct InstalledCLIForwarderTests {
  private let sourceExecutable = URL(fileURLWithPath: "/repo/.build/debug/OpenJoystickDriver")
  private let sourceBundle = URL(fileURLWithPath: "/repo/.build/debug")
  private let installedExecutable = URL(
    fileURLWithPath: "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  )

  @Test func sourceBuildCLIUsesInstalledSignedExecutable() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      arguments: ["--headless", "controller", "trace"],
      installedExecutableURL: installedExecutable,
      isExecutableFile: { $0 == self.installedExecutable.path },
      installedCLIIsCurrent: { _, _ in true }
    )

    #expect(resolution == .forward(installedExecutable))
  }

  @Test func applicationBundleExecutesItsOwnCLI() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: installedExecutable,
      mainBundleURL: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app"),
      arguments: ["--headless", "controller", "trace"],
      installedExecutableURL: installedExecutable
    ) { _ in true }

    #expect(resolution == .local)
  }

  @Test func applicationLaunchWithoutCLIArgumentsIsNotForwarded() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      arguments: [],
      installedExecutableURL: installedExecutable
    ) { _ in true }

    #expect(resolution == .local)
  }

  @Test func sourceBuildRunsLocallyWhenNoInstalledCLIExists() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      arguments: ["--headless", "diagnose", "catalog"],
      installedExecutableURL: installedExecutable
    ) { _ in false }

    #expect(resolution == .local)
  }

  @Test func symlinkToInstalledExecutableDoesNotForwardRecursively() throws {
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
      arguments: ["--headless", "status"],
      installedExecutableURL: executable
    ) { _ in true }

    #expect(resolution == .local)
  }

  @Test func staleInstalledCLIIsRejectedBeforeForwarding() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      arguments: ["--headless", "controller", "trace"],
      installedExecutableURL: installedExecutable,
      isExecutableFile: { _ in true },
      installedCLIIsCurrent: { _, _ in false }
    )

    #expect(resolution == .staleInstallation(installedExecutable))
  }

  @Test func explicitRepositoryOverrideSkipsInstalledCLI() {
    let resolution = InstalledCLIForwarder.resolve(
      currentExecutableURL: sourceExecutable,
      mainBundleURL: sourceBundle,
      arguments: ["--headless", "diagnose", "catalog"],
      installedExecutableURL: installedExecutable,
      repositoryCLIOverride: true,
      isExecutableFile: { _ in true },
      installedCLIIsCurrent: { _, _ in true }
    )

    #expect(resolution == .local)
  }

  @Test func repositorySourceFreshnessPreventsStaleForwarding() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceDirectory = root.appendingPathComponent("Sources/OpenJoystickDriver")
    let buildDirectory = root.appendingPathComponent(".build/debug")
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
    let manifest = root.appendingPathComponent("Package.swift")
    let source = sourceDirectory.appendingPathComponent("main.swift")
    let repositoryExecutable = buildDirectory.appendingPathComponent("OpenJoystickDriver")
    let installed = root.appendingPathComponent("installed-OpenJoystickDriver")
    for file in [manifest, source, repositoryExecutable, installed] {
      #expect(FileManager.default.createFile(atPath: file.path, contents: Data()))
    }
    let older = Date(timeIntervalSince1970: 100)
    let newer = Date(timeIntervalSince1970: 200)
    try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: installed.path)
    try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: manifest.path)
    try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: source.path)

    let stale = InstalledCLIForwarder.resolve(
      currentExecutableURL: repositoryExecutable,
      mainBundleURL: buildDirectory,
      arguments: ["--headless", "status"],
      installedExecutableURL: installed
    ) { _ in true }
    #expect(stale == .staleInstallation(installed))

    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 300)],
      ofItemAtPath: installed.path
    )
    let current = InstalledCLIForwarder.resolve(
      currentExecutableURL: repositoryExecutable,
      mainBundleURL: buildDirectory,
      arguments: ["--headless", "status"],
      installedExecutableURL: installed
    ) { _ in true }
    #expect(current == .forward(installed))
  }
}
