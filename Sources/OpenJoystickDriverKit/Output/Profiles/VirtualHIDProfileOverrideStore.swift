import Foundation

/// Why stored virtual HID profile overrides cannot be read.
public enum VirtualHIDProfileOverrideError: Error, Equatable, Sendable {
  /// An entry names a profile OJD does not recognize.
  case unsupportedValue(String)
  /// The stored value is not a JSON array of well-formed, unique controller-model entries.
  case unsupportedSchema
}

/// Per-controller-model and per-unit Advanced overrides of the virtual HID profile, stored in
/// `UserDefaults`.
///
/// The value under `defaultsKey` is JSON data holding an array of
/// `{"vendorID": Int, "productID": Int, "unit": String?, "profile": String}` entries, one per
/// VID:PID model and one per unit (see ``UnitIdentity``). A unit's entry wins over its model's.
/// An absent key means no overrides. When the stored value cannot be read, every controller selects
/// automatically, the store never rewrites the value, and `set` and `reset` throw the load error
/// until `resetAll()` removes the key.
///
/// Unchecked because the only stored state is `UserDefaults`, which is thread-safe.
public struct VirtualHIDProfileOverrideStore: @unchecked Sendable {
  public static let defaultsKey = "VirtualHIDProfileOverrides"

  private struct Entry: Codable {
    let vendorID: Int
    let productID: Int
    let unit: String?
    let profile: String
  }

  /// A controller model, or one unit of it when `unit` is set.
  private struct Model: Hashable {
    let vendorID: UInt16
    let productID: UInt16
    var unit: String?
  }

  /// Serializes read-modify-write updates, which `UserDefaults` alone does not make atomic.
  private static let updateLock = NSLock()

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  /// Why the stored overrides cannot be read; nil when they are absent or valid.
  public var loadError: VirtualHIDProfileOverrideError? {
    if case .failure(let error) = load() { return error }
    return nil
  }

  /// The override for one controller: the entry for `unit`, else the entry for its model. Nil
  /// when it selects automatically, including while the stored overrides cannot be read.
  public func override(
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) -> VirtualHIDProfileID? {
    guard case .success(let overrides) = load() else { return nil }
    if let unit,
      let profile = overrides[Model(vendorID: vendorID, productID: productID, unit: unit)]
    {
      return profile
    }
    return overrides[Model(vendorID: vendorID, productID: productID)]
  }

  /// The override stored for exactly this model, or this unit when `unit` is set.
  public func storedOverride(
    vendorID: UInt16,
    productID: UInt16,
    unit: String?
  ) -> VirtualHIDProfileID? {
    guard case .success(let overrides) = load() else { return nil }
    return overrides[Model(vendorID: vendorID, productID: productID, unit: unit)]
  }

  /// Stores `profile` as the override for one controller model, or for one unit of it.
  ///
  /// - Throws: The load error while the stored overrides cannot be read.
  public func set(
    _ profile: VirtualHIDProfileID,
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) throws(VirtualHIDProfileOverrideError) {
    try update { $0[Model(vendorID: vendorID, productID: productID, unit: unit)] = profile }
  }

  /// Returns one controller model, or one unit of it, to automatic selection. Resetting a unit
  /// leaves its model's override in effect.
  ///
  /// - Throws: The load error while the stored overrides cannot be read.
  public func reset(
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) throws(VirtualHIDProfileOverrideError) {
    try update { $0[Model(vendorID: vendorID, productID: productID, unit: unit)] = nil }
  }

  /// Removes every override, including a stored value that cannot be read.
  public func resetAll() {
    Self.updateLock.withLock { defaults.removeObject(forKey: Self.defaultsKey) }
  }

  private func update(
    _ change: (inout [Model: VirtualHIDProfileID]) -> Void
  ) throws(VirtualHIDProfileOverrideError) {
    Self.updateLock.lock()
    defer { Self.updateLock.unlock() }
    let loaded = try load().get()
    var overrides = loaded
    change(&overrides)
    guard overrides != loaded else { return }
    save(overrides)
  }

  private func load() -> Result<[Model: VirtualHIDProfileID], VirtualHIDProfileOverrideError> {
    guard let stored = defaults.object(forKey: Self.defaultsKey) else { return .success([:]) }
    guard let data = stored as? Data,
      let entries = try? JSONDecoder().decode([Entry].self, from: data)
    else { return .failure(.unsupportedSchema) }
    var overrides: [Model: VirtualHIDProfileID] = [:]
    for entry in entries {
      guard let vendorID = UInt16(exactly: entry.vendorID),
        let productID = UInt16(exactly: entry.productID)
      else { return .failure(.unsupportedSchema) }
      guard let profile = VirtualHIDProfileID(rawValue: entry.profile) else {
        return .failure(.unsupportedValue(entry.profile))
      }
      let model = Model(vendorID: vendorID, productID: productID, unit: entry.unit)
      guard overrides.updateValue(profile, forKey: model) == nil else {
        return .failure(.unsupportedSchema)
      }
    }
    return .success(overrides)
  }

  private func save(_ overrides: [Model: VirtualHIDProfileID]) {
    guard !overrides.isEmpty else {
      defaults.removeObject(forKey: Self.defaultsKey)
      return
    }
    let entries = overrides.sorted {
      ($0.key.vendorID, $0.key.productID, $0.key.unit ?? "")
        < ($1.key.vendorID, $1.key.productID, $1.key.unit ?? "")
    }.map {
      Entry(
        vendorID: Int($0.key.vendorID),
        productID: Int($0.key.productID),
        unit: $0.key.unit,
        profile: $0.value.rawValue
      )
    }
    // Encoding an array of integers and strings cannot fail.
    guard let data = try? JSONEncoder().encode(entries) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }
}
