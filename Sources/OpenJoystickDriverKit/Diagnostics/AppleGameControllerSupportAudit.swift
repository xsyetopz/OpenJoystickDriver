import Foundation

/// Location class for Apple's private, read-only GameController mapping database.
public enum AppleGameControllerCatalogSource: String, Codable, Sendable {
  case downloadedMobileAsset
  case preinstalledMobileAsset
  case unavailable
}

/// One exact VID/PID match observed in Apple's current-system GameController database.
///
/// Catalog presence is evidence only. Runtime support can still depend on transport,
/// firmware version, report descriptor, and GameController.framework behavior.
public struct AppleGameControllerCatalogEntry: Codable, Hashable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let identifiers: [String]
  public let transports: [String]
  public let versionNumbers: [Int]

  public init(
    vendorID: UInt16,
    productID: UInt16,
    identifiers: [String],
    transports: [String] = [],
    versionNumbers: [Int] = []
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.identifiers = identifiers.sorted()
    self.transports = transports.sorted()
    self.versionNumbers = versionNumbers.sorted()
  }
}

/// Redacted snapshot of Apple's current-system GameController mapping catalog.
public struct AppleGameControllerCatalogSnapshot: Codable, Sendable {
  public let source: AppleGameControllerCatalogSource
  public let bundleVersions: [String]
  public let entries: [AppleGameControllerCatalogEntry]
  public let skippedDeviceCount: Int
  public let warnings: [String]

  public init(
    source: AppleGameControllerCatalogSource,
    bundleVersions: [String],
    entries: [AppleGameControllerCatalogEntry],
    skippedDeviceCount: Int = 0,
    warnings: [String] = []
  ) {
    self.source = source
    self.bundleVersions = bundleVersions.sorted()
    self.entries = entries.sorted {
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      return $0.productID < $1.productID
    }
    self.skippedDeviceCount = skippedDeviceCount
    self.warnings = warnings
  }
}

/// Lightweight identity from an OJD runtime controller record.
public struct OJDControllerRecordIdentity: Codable, Hashable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let name: String

  public init(vendorID: UInt16, productID: UInt16, name: String) {
    self.vendorID = vendorID
    self.productID = productID
    self.name = name
  }
}

/// Exact current-system Apple catalog evidence for one OJD controller record.
public struct AppleGameControllerRecordAudit: Codable, Hashable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let name: String
  public let catalogListed: Bool
  public let appleIdentifiers: [String]
  public let transportConstraints: [String]
  public let versionConstraints: [Int]
}

/// Comparison of OJD records with Apple's private current-system mapping database.
public struct AppleGameControllerSupportAudit: Codable, Sendable {
  public let source: AppleGameControllerCatalogSource
  public let bundleVersions: [String]
  public let appleExactDeviceCount: Int
  public let skippedAppleDeviceCount: Int
  public let ojdRecordCount: Int
  public let catalogListedOJDRecordCount: Int
  public let records: [AppleGameControllerRecordAudit]
  public let warnings: [String]
  public let caveat: String
}

/// Reads Apple's private mapping asset without treating it as a supported API.
public enum AppleGameControllerSupportAuditor {
  private struct DeviceKey: Hashable {
    let vendorID: UInt16
    let productID: UInt16
  }

  private struct EntryAccumulator {
    var identifiers: Set<String> = []
    var transports: Set<String> = []
    var versionNumbers: Set<Int> = []
  }

  private struct AssetCandidate {
    let version: String
    let snapshot: AppleGameControllerCatalogSnapshot
  }

  private struct ProfileDocument: Decodable {
    let vendorID: Int
    let productID: Int

    enum CodingKeys: String, CodingKey {
      case vendorID = "vendor_id"
      case productID = "product_id"
    }
  }

  private static let catalogRoots: [(AppleGameControllerCatalogSource, URL)] = [
    (
      .downloadedMobileAsset,
      URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_GameController_DB1")
    ),
    (
      .preinstalledMobileAsset,
      URL(
        fileURLWithPath: "/System/Library/AssetsV2/PreinstalledAssetsV2/RequiredByOs/"
          + "com_apple_MobileAsset_GameController_DB1"
      )
    )
  ]

  public static func auditCurrentSystem() -> AppleGameControllerSupportAudit {
    audit(snapshot: currentSystemSnapshot(), records: bundledOJDRecords())
  }

  public static func currentSystemSnapshot() -> AppleGameControllerCatalogSnapshot {
    for (source, root) in catalogRoots {
      if let snapshot = loadBestAsset(at: root, source: source), !snapshot.entries.isEmpty {
        return snapshot
      }
    }
    return AppleGameControllerCatalogSnapshot(
      source: .unavailable,
      bundleVersions: [],
      entries: [],
      warnings: ["Apple GameController mapping MobileAsset was not available on this system."]
    )
  }

  public static func bundledOJDRecords() -> [OJDControllerRecordIdentity] {
    let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
    let decoder = JSONDecoder()
    var profiles: [DeviceKey: OJDControllerRecordIdentity] = [:]
    for url in urls where isControllerRecordFilename(url.lastPathComponent) {
      guard let data = try? Data(contentsOf: url),
        let document = try? decoder.decode(ProfileDocument.self, from: data),
        (1...65_535).contains(document.vendorID), (0...65_535).contains(document.productID)
      else { continue }
      let key = DeviceKey(
        vendorID: UInt16(document.vendorID),
        productID: UInt16(document.productID)
      )
      profiles[key] = OJDControllerRecordIdentity(
        vendorID: key.vendorID,
        productID: key.productID,
        name: String(format: "Controller %04x:%04x", key.vendorID, key.productID)
      )
    }
    return profiles.values.sorted {
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      return $0.productID < $1.productID
    }
  }

  private static func isControllerRecordFilename(_ name: String) -> Bool {
    guard name.count == 14, name.hasSuffix(".json") else { return false }
    let stem = name.dropLast(5)
    guard stem[stem.index(stem.startIndex, offsetBy: 4)] == "-" else { return false }
    return stem.enumerated().allSatisfy { offset, character in offset == 4 || character.isHexDigit }
  }

  public static func audit(
    snapshot: AppleGameControllerCatalogSnapshot,
    records: [OJDControllerRecordIdentity]
  ) -> AppleGameControllerSupportAudit {
    var appleByKey: [DeviceKey: AppleGameControllerCatalogEntry] = [:]
    for entry in snapshot.entries {
      let key = DeviceKey(vendorID: entry.vendorID, productID: entry.productID)
      guard let existing = appleByKey[key] else {
        appleByKey[key] = entry
        continue
      }
      appleByKey[key] = AppleGameControllerCatalogEntry(
        vendorID: key.vendorID,
        productID: key.productID,
        identifiers: Array(Set(existing.identifiers + entry.identifiers)),
        transports: Array(Set(existing.transports + entry.transports)),
        versionNumbers: Array(Set(existing.versionNumbers + entry.versionNumbers))
      )
    }

    let rows = records.map { profile in
      let entry = appleByKey[DeviceKey(vendorID: profile.vendorID, productID: profile.productID)]
      return AppleGameControllerRecordAudit(
        vendorID: profile.vendorID,
        productID: profile.productID,
        name: profile.name,
        catalogListed: entry != nil,
        appleIdentifiers: entry?.identifiers ?? [],
        transportConstraints: entry?.transports ?? [],
        versionConstraints: entry?.versionNumbers ?? []
      )
    }.sorted {
      if $0.catalogListed != $1.catalogListed { return $0.catalogListed && !$1.catalogListed }
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      return $0.productID < $1.productID
    }

    return AppleGameControllerSupportAudit(
      source: snapshot.source,
      bundleVersions: snapshot.bundleVersions,
      appleExactDeviceCount: snapshot.entries.count,
      skippedAppleDeviceCount: snapshot.skippedDeviceCount,
      ojdRecordCount: rows.count,
      catalogListedOJDRecordCount: rows.filter(\.catalogListed).count,
      records: rows,
      warnings: snapshot.warnings,
      caveat: "Private current-system catalog observation only. A missing entry does not prove "
        + "GameController incompatibility, and a listed entry does not replace a live "
        + "GCController.supportsHIDDevice or hardware test."
    )
  }

  static func snapshot(bundleInfoData: [Data], source: AppleGameControllerCatalogSource)
    -> AppleGameControllerCatalogSnapshot
  {
    var accumulators: [DeviceKey: EntryAccumulator] = [:]
    var versions: Set<String> = []
    var skippedDeviceCount = 0
    var malformedBundleCount = 0

    for data in bundleInfoData {
      guard
        let plist = try? PropertyListSerialization.propertyList(
          from: data,
          options: [],
          format: nil
        ), let dictionary = plist as? [String: Any]
      else {
        malformedBundleCount += 1
        continue
      }

      if let version = dictionary["CFBundleVersion"] as? String, !version.isEmpty {
        versions.insert(version)
      }
      guard let devices = dictionary["Devices"] as? [[String: Any]] else {
        malformedBundleCount += 1
        continue
      }

      for device in devices {
        guard let match = device["IOPropertyMatch"] as? [String: Any],
          let vendor = integer(match["VendorID"]), let product = integer(match["ProductID"]),
          (0...65_535).contains(vendor), (0...65_535).contains(product)
        else {
          skippedDeviceCount += 1
          continue
        }

        let key = DeviceKey(vendorID: UInt16(vendor), productID: UInt16(product))
        var accumulator = accumulators[key] ?? EntryAccumulator()
        if let identifier = device["Identifier"] as? String, !identifier.isEmpty {
          accumulator.identifiers.insert(identifier)
        }
        if let transport = match["Transport"] as? String, !transport.isEmpty {
          accumulator.transports.insert(transport)
        }
        if let versionNumber = integer(match["VersionNumber"]) {
          accumulator.versionNumbers.insert(versionNumber)
        }
        accumulators[key] = accumulator
      }
    }

    let entries = accumulators.map { key, accumulator in
      AppleGameControllerCatalogEntry(
        vendorID: key.vendorID,
        productID: key.productID,
        identifiers: Array(accumulator.identifiers),
        transports: Array(accumulator.transports),
        versionNumbers: Array(accumulator.versionNumbers)
      )
    }
    var warnings: [String] = []
    if malformedBundleCount > 0 {
      warnings.append(
        "\(malformedBundleCount) GameController catalog bundle(s) could not be parsed."
      )
    }
    if skippedDeviceCount > 0 {
      warnings.append(
        "\(skippedDeviceCount) catalog device record(s) lacked an exact numeric VID/PID."
      )
    }
    return AppleGameControllerCatalogSnapshot(
      source: source,
      bundleVersions: Array(versions),
      entries: entries,
      skippedDeviceCount: skippedDeviceCount,
      warnings: warnings
    )
  }

  private static func loadBestAsset(at root: URL, source: AppleGameControllerCatalogSource)
    -> AppleGameControllerCatalogSnapshot?
  {
    let fileManager = FileManager.default
    guard
      let assetURLs = try? fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else { return nil }

    let candidates = assetURLs.compactMap { assetURL -> AssetCandidate? in
      guard assetURL.pathExtension == "asset" else { return nil }
      let assetDataURL = assetURL.appendingPathComponent("AssetData", isDirectory: true)
      guard
        let bundleURLs = try? fileManager.contentsOfDirectory(
          at: assetDataURL,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
      else { return nil }
      let infoData = bundleURLs.compactMap { bundleURL -> Data? in
        guard bundleURL.pathExtension == "bundle" else { return nil }
        return try? Data(contentsOf: bundleURL.appendingPathComponent("Info.plist"))
      }
      guard !infoData.isEmpty else { return nil }
      let snapshot = snapshot(bundleInfoData: infoData, source: source)
      let version = snapshot.bundleVersions.max(by: versionIsLessThan) ?? "0"
      return AssetCandidate(version: version, snapshot: snapshot)
    }

    return candidates.max { versionIsLessThan($0.version, $1.version) }?.snapshot
  }

  private static func integer(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? String { return Int(value) }
    return nil
  }

  private static func versionIsLessThan(_ left: String, _ right: String) -> Bool {
    let leftParts = left.split(separator: ".").map { Int($0) ?? 0 }
    let rightParts = right.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(leftParts.count, rightParts.count)
    for index in 0..<count {
      let lhs = index < leftParts.count ? leftParts[index] : 0
      let rhs = index < rightParts.count ? rightParts[index] : 0
      if lhs != rhs { return lhs < rhs }
    }
    return left < right
  }
}
