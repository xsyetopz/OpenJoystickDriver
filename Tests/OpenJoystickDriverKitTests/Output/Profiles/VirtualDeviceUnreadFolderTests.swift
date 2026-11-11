import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A `Personas` folder beside the `VirtualDevices` folder is not read, and the store lists it
/// with the reason instead of passing over it.
struct VirtualDeviceUnreadFolderTests {
  private let localization = Localization()

  private func withSupportFolder(_ body: (URL) throws -> Void) throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-unread-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    try body(support)
  }

  private static let document = PropertyListFixture.bytes(
    json: """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "VirtualDevice",
        "match": {"vendorID": 4617, "productID": 1}, "persona": "SDLCompatible"}
      """
  )

  @Test
  func aPersonasFolderIsListedAndItsFilesAreNotRead() throws {
    try withSupportFolder { support in
      let unread = support.appendingPathComponent(
        VirtualHIDProfileOverrideStore.unreadFolderName,
        isDirectory: true
      )
      try FileManager.default.createDirectory(at: unread, withIntermediateDirectories: true)
      try Self.document.write(to: unread.appendingPathComponent("1209-0001.plist"))
      let devices = support.appendingPathComponent(
        VirtualHIDProfileOverrideStore.directoryName,
        isDirectory: true
      )
      let store = VirtualHIDProfileOverrideStore(directory: devices)

      #expect(store.persona(vendorID: 0x1209, productID: 0x0001) == nil)
      let listed = try #require(store.problems.first)
      #expect(store.problems.count == 1)
      #expect(listed.url.lastPathComponent == "Personas")
      #expect(
        listed.problem
          == localization.formatted("status.virtualDeviceFolderNotRead", arguments: [devices.path])
      )
      #expect(listed.problem?.contains(devices.path) == true)
    }
  }

  @Test
  func aPersonasFolderWithNoVisibleFilesListsNothing() throws {
    try withSupportFolder { support in
      let unread = support.appendingPathComponent(
        VirtualHIDProfileOverrideStore.unreadFolderName,
        isDirectory: true
      )
      try FileManager.default.createDirectory(at: unread, withIntermediateDirectories: true)
      try Data().write(to: unread.appendingPathComponent(".DS_Store"))
      let devices = support.appendingPathComponent("VirtualDevices", isDirectory: true)

      #expect(VirtualHIDProfileOverrideStore(directory: devices).problems.isEmpty)
    }
  }

  @Test
  func noPersonasFolderListsNothing() throws {
    try withSupportFolder { support in
      let devices = support.appendingPathComponent("VirtualDevices", isDirectory: true)
      try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
      try Self.document.write(to: devices.appendingPathComponent("1209-0001.plist"))
      try Data().write(to: support.appendingPathComponent("Personas"))
      let store = VirtualHIDProfileOverrideStore(directory: devices)

      #expect(store.problems.isEmpty)
      #expect(store.persona(vendorID: 0x1209, productID: 0x0001)?.descriptor == .sdlCompatible)
    }
  }
}
