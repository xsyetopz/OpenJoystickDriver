import Foundation
import IOKit
import Security

/// Whether the embedded Apple Development profile authorizes virtual HID on this Mac.
///
/// `SecTaskCopyValueForEntitlement` can report `com.apple.developer.hid.virtual.device`
/// while AMFI still refuses `HIDVirtualDevice` because the development profile's
/// device list does not include this host. Apple Silicon development profiles store
/// the Provisioning UDID (IODeviceTree `chip-id` + `unique-chip-id`); Intel profiles
/// store the Hardware UUID (`IOPlatformUUID`). Do not log device identifiers.
public enum VirtualHIDProvisioningHost: Sendable {
  public enum Authorization: Equatable, Sendable {
    case unrestricted
    case includesHost
    case excludesHost
    case unavailable
  }

  public static func currentAuthorization(bundle: Bundle = .main) -> Authorization {
    guard let url = bundle.url(forResource: "embedded", withExtension: "provisionprofile"),
      let data = try? Data(contentsOf: url),
      let plist = cmsPlist(from: data)
    else { return .unavailable }
    return authorization(profilePlist: plist, hostIDs: hostIdentifiers())
  }

  public static func authorization(
    profilePlist: [String: Any],
    hostIDs: [String]
  ) -> Authorization {
    if profilePlist["ProvisionsAllDevices"] as? Bool == true { return .unrestricted }
    guard let devices = profilePlist["ProvisionedDevices"] as? [String] else {
      return .unrestricted
    }
    let hosts = hostIDs.filter { !$0.isEmpty }
    guard !hosts.isEmpty else { return .unavailable }
    let hostKeys = Set(hosts.map(normalizedDeviceID))
    return devices.contains { hostKeys.contains(normalizedDeviceID($0)) }
      ? .includesHost : .excludesHost
  }

  public static func platformUUID() -> String? {
    let service = IOServiceGetMatchingService(
      kIOMasterPortDefault,
      IOServiceMatching("IOPlatformExpertDevice")
    )
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard
      let uuid = IORegistryEntryCreateCFProperty(
        service,
        "IOPlatformUUID" as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? String,
      !uuid.isEmpty
    else { return nil }
    return uuid
  }

  static func hostIdentifiers() -> [String] {
    [platformUUID(), provisioningUDID()].compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }
  }

  /// Apple Silicon Provisioning UDID from DeviceTree `chosen`, matching System Information.
  static func provisioningUDID() -> String? {
    let chosen = IORegistryEntryFromPath(kIOMasterPortDefault, "IODeviceTree:/chosen")
    guard chosen != 0 else { return nil }
    defer { IOObjectRelease(chosen) }
    guard
      let chipID = littleEndianUInt32(dataProperty(chosen, "chip-id")),
      let uniqueChipID = littleEndianUInt64(dataProperty(chosen, "unique-chip-id"))
    else { return nil }
    return "\(paddedHex(UInt64(chipID), width: 8))-\(paddedHex(uniqueChipID, width: 16))"
  }

  static func normalizedDeviceID(_ value: String) -> String {
    value.replacingOccurrences(of: "-", with: "").lowercased()
  }

  static func cmsPlist(from data: Data) -> [String: Any]? {
    var decoder: CMSDecoder?
    guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
    let update = data.withUnsafeBytes { buffer -> OSStatus in
      guard let base = buffer.baseAddress else { return errSecParam }
      return CMSDecoderUpdateMessage(decoder, base, buffer.count)
    }
    guard update == errSecSuccess else { return nil }
    guard CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }
    var content: CFData?
    guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content else { return nil }
    return try? PropertyListSerialization.propertyList(
      from: content as Data,
      options: [],
      format: nil
    ) as? [String: Any]
  }

  private static func dataProperty(_ entry: io_registry_entry_t, _ key: String) -> Data? {
    IORegistryEntryCreateCFProperty(
      entry,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? Data
  }

  private static func littleEndianUInt32(_ data: Data?) -> UInt32? {
    guard let data, data.count >= 4 else { return nil }
    return data.prefix(4).enumerated().reduce(into: UInt32(0)) { value, item in
      value |= UInt32(item.element) << (item.offset * 8)
    }
  }

  private static func littleEndianUInt64(_ data: Data?) -> UInt64? {
    guard let data, data.count >= 8 else { return nil }
    return data.prefix(8).enumerated().reduce(into: UInt64(0)) { value, item in
      value |= UInt64(item.element) << (item.offset * 8)
    }
  }

  private static func paddedHex(_ value: UInt64, width: Int) -> String {
    let digits = String(value, radix: 16)
    guard digits.count < width else { return digits }
    return String(repeating: "0", count: width - digits.count) + digits
  }
}
