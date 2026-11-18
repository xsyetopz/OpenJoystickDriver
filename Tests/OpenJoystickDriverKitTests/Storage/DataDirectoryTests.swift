import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DataDirectoryTests {
  @Test
  func rootedDirectorySeparatesEveryLocationUnderItsRoot() {
    let root = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let directory = RootedDataDirectory(root: root)
    let urls = DataLocation.allCases.map { directory.url(for: $0) }
    #expect(Set(urls).count == DataLocation.allCases.count)
    #expect(urls.allSatisfy { $0.path.hasPrefix(root.path + "/") })
    #expect(
      directory.fileURL("a.json", in: .applicationData)
        == root.appendingPathComponent("applicationData/a.json")
    )
  }

  @Test
  func macOSDirectoryKeepsShippedLocations() {
    let directory = MacOSDataDirectory()
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(
      directory.url(for: .applicationData).path
        == home + "/Library/Application Support/OpenJoystickDriver"
    )
    #expect(directory.url(for: .cache).path == home + "/Library/Caches/OpenJoystickDriver")
    #expect(directory.url(for: .logs).path == home + "/Library/Logs/OpenJoystickDriver")
    #expect(directory.url(for: .home).path == home)
    #expect(directory.url(for: .sharedTemporary).path == "/tmp")
    #expect(directory.url(for: .runtime).path.hasPrefix("/var/folders/"))
    let controllers = directory.url(for: .applicationData)
      .appendingPathComponent("Controllers", isDirectory: true)
    #expect(ControllerRecordSet.userDirectory == controllers)
    #expect(
      LocalServiceRPCTransport.defaultSocketPath == "/tmp/com.openjoystickdriver.\(geteuid()).rpc"
    )
  }

  @Test
  func logAndSocketPathsFollowInjectedDirectory() {
    let directory = RootedDataDirectory(
      root: MacOSDataDirectory().url(for: .temporary).appendingPathComponent(UUID().uuidString)
    )
    #expect(
      ApplicationServiceLogService.url(for: .standardError, dataDirectory: directory)
        == directory.url(for: .logs).appendingPathComponent("OpenJoystickDriver.err.log")
    )
    #expect(
      LocalServiceRPCTransport.socketPath(in: directory).hasPrefix(
        directory.url(for: .sharedTemporary).path
      )
    )
  }
}
