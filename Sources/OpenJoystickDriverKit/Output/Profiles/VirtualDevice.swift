import Foundation

/// The HID report layout a persona publishes.
enum VirtualDeviceLayout: String, CaseIterable, Sendable {
  /// The generic OJD gamepad layout, ``OJDGenericGamepadFormat``.
  case ojdGenericGamepad = "OJDGenericGamepad"
  /// The Xbox One GIP layout, ``XboxOneGIPHIDReportFormat``.
  case xboxOneGIP = "XboxOneGIP"
  /// The Xbox Series Bluetooth layout, ``XboxSeriesBluetoothHIDReportFormat``.
  case xboxSeriesBluetooth = "XboxSeriesBluetooth"
}

/// One `VirtualDevice` document (`virtual-device.schema.json`): either the definition of a
/// persona, or, with `match`, the selection of a persona for one controller model or unit.
struct VirtualDevice: Equatable, Sendable {
  /// The identity a document sets over the persona's.
  struct Identity: Equatable, Sendable {
    /// The USB vendor ID.
    let vendorID: UInt16
    /// The USB product ID.
    let productID: UInt16
    /// The version number; nil when the document sets none.
    let versionNumber: Int?
    /// The product name.
    let productName: String
    /// The manufacturer name.
    let manufacturer: String
  }

  /// The `kind` of a virtual device document.
  static let kind = "VirtualDevice"

  /// The persona the document defines or selects.
  let persona: VirtualHIDProfileID
  /// The controller model or unit this document selects the persona for; nil for a definition.
  let match: VirtualHIDProfileOverrideStore.Model?
  /// The report layout of a definition; nil for a selection.
  let layout: VirtualDeviceLayout?
  /// The transport the device reports, for a definition; nil for a selection.
  let transport: String?
  /// The glyph family of the published product, for a definition; nil for a selection.
  let labels: VirtualIdentityGlyphFamily?
  /// Whether SDL recognizes the published device with its default hints; nil for a selection.
  let worksWithDefaultSDLHints: Bool?
  /// The identity of a definition; nil for a selection.
  let identity: Identity?

  /// The bundled definitions, by persona.
  static let bundled: [VirtualHIDProfileID: Self] = {
    do { return try loadBundled() } catch {
      fatalError("[VirtualDevice] Invalid bundled virtual devices: \(error)")
    }
  }()

  /// The bundled definition of `persona`.
  static func definition(of persona: VirtualHIDProfileID) -> Self {
    guard let device = bundled[persona] else {
      fatalError("[VirtualDevice] No bundled virtual device for \(persona.rawValue)")
    }
    return device
  }

  /// Decodes the bundled definition of every persona.
  ///
  /// - Throws: `ControllerRecordProblem` when a record is missing, does not decode, or does not
  ///   define its persona.
  private static func loadBundled() throws -> [VirtualHIDProfileID: Self] {
    var devices: [VirtualHIDProfileID: Self] = [:]
    for persona in VirtualHIDProfileID.allCases {
      guard let url = Bundle.module.url(forResource: persona.bundledFileName, withExtension: "json")
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "no record for \(persona.rawValue)"
        )
      }
      let device = try decode(
        Data(contentsOf: url),
        source: .file(url.lastPathComponent),
        requiresMatch: false
      )
      guard device.match == nil, device.persona == persona else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "\(url.lastPathComponent) must define \(persona.rawValue)"
        )
      }
      devices[persona] = device
    }
    return devices
  }

  /// The identity this definition publishes.
  var profile: VirtualDeviceProfile? {
    guard let identity, let transport, let labels else { return nil }
    return VirtualDeviceProfile(
      vendorID: identity.vendorID,
      productID: identity.productID,
      versionNumber: identity.versionNumber ?? 0,
      productName: identity.productName,
      manufacturer: identity.manufacturer,
      transport: transport,
      glyphFamily: labels
    )
  }
}

extension VirtualHIDProfileID {
  /// The name of the bundled record file, without extension.
  var bundledFileName: String {
    switch self {
    case .generic: "virtual-device.generic"
    case .sdlCompatible: "virtual-device.sdl-compatible"
    case .gameControllerCompatible: "virtual-device.game-controller-compatible"
    }
  }
}
