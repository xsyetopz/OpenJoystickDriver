import Foundation

/// Where a HID pad's input mapping comes from, and the facts of the database line when one drives
/// it.
public struct InputMapping: Codable, Equatable, Sendable {
  /// The source of the mapping.
  public enum Source: String, Codable, Sendable {
    /// A controller record from the catalog, a package or the user.
    case record = "Record"
    /// A converted SDL_GameControllerDB line.
    case sdlGameControllerDB = "SDLGameControllerDB"
    /// The one standard HID usage map.
    case standardHIDUsageMap = "StandardHIDUsageMap"
    /// No mapping applies because the pad does not bind.
    case none = "None"
  }

  /// The source of the mapping.
  public let source: Source
  /// The SDL GUID the database was searched with; nil when the pad has no USB identity or the
  /// source is a record.
  public let guid: String?
  /// The tier at which a database line matched; nil when none did.
  public let match: SDLMatchTier?
  /// The database fields the conversion cannot express, as the line names them.
  public let unmapped: [String]
  /// Why a matching line was rejected, so the pad keeps the standard map; nil otherwise.
  public let rejection: String?

  /// The mapping of a pad with a controller record.
  static let record = InputMapping(
    source: .record,
    guid: nil,
    match: nil,
    unmapped: [],
    rejection: nil
  )

  /// The mapping of a pad with neither a record nor a database line.
  static let standardHIDUsageMap = InputMapping(
    source: .standardHIDUsageMap,
    guid: nil,
    match: nil,
    unmapped: [],
    rejection: nil
  )
}

/// What the database gives an unrecorded HID pad that passes the descriptor contract.
struct SDLBindingResolution: Equatable, Sendable {
  /// The mapping to report.
  let inputMapping: InputMapping
  /// The converted usage map; nil when the pad keeps the standard map.
  let usageMap: HIDUsageMap?
}

extension SDLGameControllerDatabase {
  /// The GUID of `device`, or nil when it lacks a vendor or product ID.
  static func guid(of device: PhysicalDevice) -> SDLGUID? {
    guard let vendorID = device.vendorID, let productID = device.productID else { return nil }
    return SDLGUID(
      vendorID: vendorID,
      productID: productID,
      version: device.deviceRelease ?? 0,
      manufacturer: device.manufacturer,
      product: device.productName ?? ""
    )
  }

  /// The line for `device`, if any.
  func match(for device: PhysicalDevice) -> SDLDatabaseMatch? {
    Self.guid(of: device).flatMap(match)
  }

  /// Converts the line for `device` against the elements of `interface`.
  ///
  /// With no line the pad keeps the standard map; a line that cannot be converted leaves it there
  /// with the reason.
  func resolve(
    device: PhysicalDevice,
    interface: PhysicalInterfaceSignature
  ) -> SDLBindingResolution {
    let guid = Self.guid(of: device)
    guard let guid, let line = match(guid) else {
      return SDLBindingResolution(
        inputMapping: InputMapping(
          source: .standardHIDUsageMap,
          guid: guid?.description,
          match: nil,
          unmapped: [],
          rejection: nil
        ),
        usageMap: nil
      )
    }
    do {
      let converted = try SDLMappingConverter.convert(
        fields: line.fields,
        elements: interface.hidLayout?.elements ?? []
      )
      return SDLBindingResolution(
        inputMapping: InputMapping(
          source: .sdlGameControllerDB,
          guid: line.guid.description,
          match: line.tier,
          unmapped: converted.unmapped,
          rejection: nil
        ),
        usageMap: converted.usageMap
      )
    } catch let rejection {
      return SDLBindingResolution(
        inputMapping: InputMapping(
          source: .standardHIDUsageMap,
          guid: line.guid.description,
          match: line.tier,
          unmapped: [],
          rejection: rejection.reason
        ),
        usageMap: nil
      )
    }
  }
}
