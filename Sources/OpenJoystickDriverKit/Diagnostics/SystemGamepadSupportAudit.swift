import Foundation

/// Location class for Apple's private, read-only GameController mapping database.
public enum SystemGamepadCatalogSource: String, Codable, Sendable {
  /// The catalog that the OS downloaded.
  case downloadedMobileAsset = "DownloadedMobileAsset"
  /// The catalog that ships with the OS.
  case preinstalledMobileAsset = "PreinstalledMobileAsset"
  /// The system has no readable catalog.
  case unavailable = "Unavailable"
}

/// One exact VID/PID match observed in Apple's current-system GameController database.
///
/// Catalog presence is evidence only. Runtime support can still depend on transport,
/// firmware version, report descriptor, and GameController.framework behavior.
public struct SystemGamepadCatalogEntry: Codable, Hashable, Sendable {
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16
  /// The catalog identifiers of the device, sorted.
  public let identifiers: [String]
  /// The transports that the entry limits the device to, sorted; empty when it names none.
  public let transports: [String]
  /// The version numbers that the entry limits the device to, sorted; empty when it names none.
  public let versionNumbers: [Int]

  /// Creates an entry; it sorts the lists.
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
public struct SystemGamepadCatalogSnapshot: Codable, Sendable {
  /// Where the catalog was read from.
  public let source: SystemGamepadCatalogSource
  /// The `CFBundleVersion` of each bundle read, sorted.
  public let bundleVersions: [String]
  /// The devices with an exact vendor and product ID, sorted by vendor ID and product ID.
  public let entries: [SystemGamepadCatalogEntry]
  /// The catalog devices without an exact numeric vendor and product ID.
  public let skippedDeviceCount: Int
  /// The problems met while reading the catalog.
  public let warnings: [String]

  /// Creates a snapshot; it sorts the bundle versions and the entries.
  public init(
    source: SystemGamepadCatalogSource,
    bundleVersions: [String],
    entries: [SystemGamepadCatalogEntry],
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

/// Exact current-system Apple catalog evidence for one OJD controller record.
public struct SystemGamepadRecordAudit: Codable, Hashable, Sendable {
  /// The USB vendor ID of the OJD controller record.
  public let vendorID: UInt16
  /// The USB product ID of the OJD controller record.
  public let productID: UInt16
  /// The record's name for the controller, from its vendor and product IDs.
  public let name: String
  /// Whether the system catalog lists the vendor and product ID.
  public let catalogListed: Bool
  /// The catalog identifiers of the device; empty when it is not listed.
  public let systemIdentifiers: [String]
  /// The transports the catalog limits the device to; empty when it names none.
  public let transportConstraints: [String]
  /// The version numbers the catalog limits the device to; empty when it names none.
  public let versionConstraints: [Int]
}

/// Comparison of OJD records with Apple's private current-system mapping database.
public struct SystemGamepadSupportAudit: Codable, Sendable {
  /// Where the catalog was read from.
  public let source: SystemGamepadCatalogSource
  /// The `CFBundleVersion` of each catalog bundle read.
  public let bundleVersions: [String]
  /// The number of devices with an exact vendor and product ID in the catalog.
  public let systemExactDeviceCount: Int
  /// The number of catalog devices without an exact numeric vendor and product ID.
  public let skippedSystemDeviceCount: Int
  /// The number of OJD controller records.
  public let ojdRecordCount: Int
  /// The number of OJD controller records that the catalog lists.
  public let catalogListedOJDRecordCount: Int
  /// One audit per OJD controller record; listed records come first.
  public let records: [SystemGamepadRecordAudit]
  /// The problems met while reading the catalog.
  public let warnings: [String]
}

/// Deserializes Apple's private mapping plists, extracting only selected
/// redacted keys without treating the asset as a supported API.
public enum SystemGamepadSupportAuditor {
  /// The values collected for one vendor and product ID.
  private struct EntryAccumulator {
    /// The identifiers of the device.
    var identifiers: Set<String> = []
    /// The transports the entry names.
    var transports: Set<String> = []
    /// The version numbers the entry names.
    var versionNumbers: Set<Int> = []
  }

  /// The catalog of one asset.
  private struct AssetCandidate {
    /// The highest bundle version of the asset.
    let version: String
    /// The devices of the asset.
    let snapshot: SystemGamepadCatalogSnapshot
  }

  /// The folders that hold the catalog assets, in the order to try them.
  private static let catalogRoots: [(SystemGamepadCatalogSource, URL)] = [
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
    ),
  ]

  /// Compares the current system's catalog with the OJD controller records.
  public static func auditCurrentSystem() -> SystemGamepadSupportAudit {
    audit(snapshot: currentSystemSnapshot(), records: bundledOJDRecords())
  }

  /// The catalog of the current system: the downloaded assets first, then the preinstalled ones.
  ///
  /// It reads the newest asset of the first folder that gives any entry, and returns an
  /// `Unavailable` snapshot with a warning when none does.
  public static func currentSystemSnapshot() -> SystemGamepadCatalogSnapshot {
    for (source, root) in catalogRoots {
      if let snapshot = loadBestAsset(at: root, source: source), !snapshot.entries.isEmpty {
        return snapshot
      }
    }
    return SystemGamepadCatalogSnapshot(
      source: .unavailable,
      bundleVersions: [],
      entries: [],
      warnings: ["The system gamepad mapping catalog was not available on this system."]
    )
  }

  /// The models of the bundled controller catalog, in ID order.
  public static func bundledOJDRecords() -> [ControllerModelID] {
    ControllerRecordSet.bundled.records.keys.sorted()
  }

  /// Compares `snapshot` with `records`.
  ///
  /// An entry that the snapshot lists twice for one ID merges into one. The rows list the records
  /// that the catalog lists first, then sort by vendor ID and product ID.
  public static func audit(
    snapshot: SystemGamepadCatalogSnapshot,
    records: [ControllerModelID]
  ) -> SystemGamepadSupportAudit {
    var appleByKey: [ControllerModelID: SystemGamepadCatalogEntry] = [:]
    for entry in snapshot.entries {
      let key = ControllerModelID(vendorID: entry.vendorID, productID: entry.productID)
      guard let existing = appleByKey[key] else {
        appleByKey[key] = entry
        continue
      }
      appleByKey[key] = SystemGamepadCatalogEntry(
        vendorID: key.vendorID,
        productID: key.productID,
        identifiers: Array(Set(existing.identifiers + entry.identifiers)),
        transports: Array(Set(existing.transports + entry.transports)),
        versionNumbers: Array(Set(existing.versionNumbers + entry.versionNumbers))
      )
    }

    let rows = records.map { model in
      let entry = appleByKey[model]
      return SystemGamepadRecordAudit(
        vendorID: model.vendorID,
        productID: model.productID,
        name: unsafe String(format: "Controller %04x:%04x", model.vendorID, model.productID),
        catalogListed: entry != nil,
        systemIdentifiers: entry?.identifiers ?? [],
        transportConstraints: entry?.transports ?? [],
        versionConstraints: entry?.versionNumbers ?? []
      )
    }.sorted {
      if $0.catalogListed != $1.catalogListed { return $0.catalogListed && !$1.catalogListed }
      if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
      return $0.productID < $1.productID
    }

    return SystemGamepadSupportAudit(
      source: snapshot.source,
      bundleVersions: snapshot.bundleVersions,
      systemExactDeviceCount: snapshot.entries.count,
      skippedSystemDeviceCount: snapshot.skippedDeviceCount,
      ojdRecordCount: rows.count,
      catalogListedOJDRecordCount: rows.filter(\.catalogListed).count,
      records: rows,
      warnings: snapshot.warnings
    )
  }

  /// The catalog read from the `Info.plist` contents of GameController bundles.
  ///
  /// A bundle that does not parse or lists no devices, and a device without an exact numeric vendor
  /// and product ID, add a warning.
  static func snapshot(
    bundleInfoData: [Data],
    source: SystemGamepadCatalogSource
  ) -> SystemGamepadCatalogSnapshot {
    var accumulators: [ControllerModelID: EntryAccumulator] = [:]
    var versions: Set<String> = []
    var skippedDeviceCount = 0
    var malformedBundleCount = 0

    for data in bundleInfoData {
      guard
        let plist = try? unsafe PropertyListSerialization.propertyList(
          from: data,
          options: 0,
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

        let key = ControllerModelID(vendorID: UInt16(vendor), productID: UInt16(product))
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
      SystemGamepadCatalogEntry(
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
    return SystemGamepadCatalogSnapshot(
      source: source,
      bundleVersions: Array(versions),
      entries: entries,
      skippedDeviceCount: skippedDeviceCount,
      warnings: warnings
    )
  }

  /// The snapshot of the asset with the highest bundle version under `root`; nil when `root` cannot
  /// be read.
  private static func loadBestAsset(
    at root: URL,
    source: SystemGamepadCatalogSource
  ) -> SystemGamepadCatalogSnapshot? {
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

  /// `value` as an integer, from an integer or an integer text; nil otherwise.
  private static func integer(_ value: Any?) -> Int? {
    if let number = value as? Int { return number }
    if let text = value as? String { return Int(text) }
    return nil
  }

  /// Whether the dotted version `left` sorts before `right`; a part that is not a number counts as
  /// 0.
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
