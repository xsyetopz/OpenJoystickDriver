import Foundation

@testable import OpenJoystickDriverKit

/// A temporary application-support folder with the user's `Controllers`, `VirtualDevices`, and
/// `Profiles` folders, the `Packages` store, and a `Staging` folder where packages are built.
struct ModPackageFixture {
  let root = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
    "ojd-packages-\(UUID().uuidString)",
    isDirectory: true
  )

  var controllers: URL { root.appendingPathComponent("Controllers", isDirectory: true) }
  var virtualDevices: URL { root.appendingPathComponent("VirtualDevices", isDirectory: true) }
  var profiles: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
  var packages: URL { root.appendingPathComponent("Packages", isDirectory: true) }

  /// Runs `body` with a fixture and removes it afterwards.
  static func with(_ body: (Self) throws -> Void) throws {
    let fixture = Self()
    try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try body(fixture)
  }

  /// The store over `Packages`, running as `version`.
  func store(running version: String = "0.6.0") -> ModPackageStore {
    ModPackageStore(directory: packages, runningVersion: version)
  }

  /// A Controller record for an identity the bundled catalog does not have.
  static func record(_ vendorID: Int, _ productID: Int) throws -> (name: String, data: Data) {
    let document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": vendorID,
      "productID": productID, "modes": [["id": "default", "protocol": ["family": "XboxGIP"]]],
    ]
    return (
      String(format: "%04x-%04x.json", vendorID, productID),
      try JSONSerialization.data(withJSONObject: document)
    )
  }

  /// A ControllerPatch for `vendorID` and `productID` that merges `body`.
  static func patch(
    _ vendorID: Int,
    _ productID: Int,
    _ body: [String: Any]
  ) throws -> (name: String, data: Data) {
    let identity = ControllerModelID(vendorID: UInt16(vendorID), productID: UInt16(productID))
    let document = ControllerPatch.document(selector: .identity(identity), body: body)
    return (
      ControllerPatch.Selector.identity(identity).fileName,
      try JSONSerialization.data(withJSONObject: document)
    )
  }

  /// A persona that selects `descriptor` for one controller model.
  static func persona(
    _ vendorID: Int,
    _ productID: Int,
    descriptor: String = "Generic"
  ) -> (name: String, data: Data) {
    let text =
      #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","#
      + #""kind":"\#(VirtualHIDProfileOverrideStore.kind)","#
      + #""match":{"vendorID":\#(vendorID),"productID":\#(productID)},"#
      + #""persona":"\#(descriptor)"}"#
    return (String(format: "%04x-%04x.json", vendorID, productID), Data(text.utf8))
  }

  /// A remapping profile document.
  static func profile(
    id: UUID = UUID(),
    name: String
  ) throws -> (name: String, data: Data) {
    let profile = RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    return ("\(name).json", Data(try RemappingProfileFileStore.encodedPlist(profile).utf8))
  }

  /// Writes `files` into `folder/kind`.
  func write(_ files: [(name: String, data: Data)], kind: String, in folder: URL) throws {
    guard !files.isEmpty else { return }
    let directory = folder.appendingPathComponent(kind, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for file in files { try file.data.write(to: directory.appendingPathComponent(file.name)) }
  }

  /// A package folder in `Staging` whose manifest lists exactly the files it holds, unless
  /// `manifest` overrides a field.
  @discardableResult
  func makePackage(
    _ name: String = "arcade-pack",
    version: String = "1.0.0",
    requires: [String: Any] = ["minimum": "0.6.0"],
    controllers: [(name: String, data: Data)] = [],
    patches: [(name: String, data: Data)] = [],
    virtualDevices: [(name: String, data: Data)] = [],
    profiles: [(name: String, data: Data)] = [],
    manifest overrides: [String: Any] = [:]
  ) throws -> URL {
    let folder = root.appendingPathComponent("Staging/\(UUID().uuidString)/\(name)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try write(controllers + patches, kind: "Controllers", in: folder)
    try write(virtualDevices, kind: "VirtualDevices", in: folder)
    try write(profiles, kind: "Profiles", in: folder)
    var manifest: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind, "name": name,
      "version": version, "author": "Tester", "requires": requires,
    ]
    if !controllers.isEmpty { manifest["controllers"] = controllers.map(\.name) }
    if !patches.isEmpty { manifest["patches"] = patches.map(\.name) }
    if !virtualDevices.isEmpty { manifest["virtualDevices"] = virtualDevices.map(\.name) }
    if !profiles.isEmpty { manifest["profiles"] = profiles.map(\.name) }
    for (key, value) in overrides { manifest[key] = value }
    try JSONSerialization.data(withJSONObject: manifest).write(
      to: folder.appendingPathComponent("mod.json")
    )
    return folder
  }
}
