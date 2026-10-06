import Foundation

/// Arguments of `setVirtualHIDProfileOverride`: the controller selector, the requested
/// profile's raw identifier, such as `hid-generic`, and whether the override is for the selected
/// unit only (see ``UnitIdentity``) instead of its model. An absent `unit` means the model.
public struct LocalServiceRPCVirtualHIDProfileOverrideArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let runtimeIdentifier: String?
  public let profile: String
  public let unit: Bool

  public init(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String? = nil,
    profile: String,
    unit: Bool = false
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
    self.profile = profile
    self.unit = unit
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    vendorID = try container.decode(Int.self, forKey: .vendorID)
    productID = try container.decode(Int.self, forKey: .productID)
    runtimeIdentifier = try container.decodeIfPresent(String.self, forKey: .runtimeIdentifier)
    profile = try container.decode(String.self, forKey: .profile)
    unit = try container.decodeIfPresent(Bool.self, forKey: .unit) ?? false
  }
}

/// Arguments of `resetVirtualHIDProfileOverride`: the controller selector and whether to reset
/// the selected unit's override instead of its model's. An absent `unit` means the model.
public struct LocalServiceRPCVirtualHIDProfileOverrideResetArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let runtimeIdentifier: String?
  public let unit: Bool

  public init(vendorID: Int, productID: Int, runtimeIdentifier: String? = nil, unit: Bool = false) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
    self.unit = unit
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    vendorID = try container.decode(Int.self, forKey: .vendorID)
    productID = try container.decode(Int.self, forKey: .productID)
    runtimeIdentifier = try container.decodeIfPresent(String.self, forKey: .runtimeIdentifier)
    unit = try container.decodeIfPresent(Bool.self, forKey: .unit) ?? false
  }
}

/// Why a virtual HID profile override request did not take full effect.
///
/// Encoded as `{"code": String, "detail": String?}`; only `activation-failed` carries a detail.
public enum VirtualHIDProfileOverrideFailure: Codable, Equatable, Sendable {
  /// The requested profile identifier names no profile. Nothing was stored.
  case unknownProfile
  /// No connected controller of the model matches the selector, a unit request selected a
  /// controller without a unit ID, or the selected controller disconnected during the request.
  /// The stored override is unchanged, except when the controller disconnected after every
  /// retarget succeeded.
  case controllerNotFound
  /// The override is stored, but the controller cannot satisfy it, so automatic selection runs.
  case overrideRejectedByController
  /// A replacement backend failed or timed out; the prior stored value is restored and every
  /// retargeted controller of the model returns to it. The detail also reports a failed restore.
  case activationFailed(detail: String)
  /// The override is stored, but no automatic virtual output is live to apply it to.
  case outputDisabled
  /// The service stopped before or during the request. The stored override is unchanged.
  case serverStopped
  /// The stored overrides cannot be read or written. Nothing was stored.
  case persistenceFailed

  /// The wire identifier of the failure.
  public var code: String {
    switch self {
    case .unknownProfile: "unknown-profile"
    case .controllerNotFound: "controller-not-found"
    case .overrideRejectedByController: "override-rejected-by-controller"
    case .activationFailed: "activation-failed"
    case .outputDisabled: "output-disabled"
    case .serverStopped: "server-stopped"
    case .persistenceFailed: "persistence-failed"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case code
    case detail
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let code = try container.decode(String.self, forKey: .code)
    switch code {
    case "unknown-profile": self = .unknownProfile
    case "controller-not-found": self = .controllerNotFound
    case "override-rejected-by-controller": self = .overrideRejectedByController
    case "activation-failed":
      self = .activationFailed(detail: try container.decode(String.self, forKey: .detail))
    case "output-disabled": self = .outputDisabled
    case "server-stopped": self = .serverStopped
    case "persistence-failed": self = .persistenceFailed
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .code,
        in: container,
        debugDescription: "Unknown virtual HID profile override failure: \(code)"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(code, forKey: .code)
    if case .activationFailed(let detail) = self { try container.encode(detail, forKey: .detail) }
  }
}

/// Result of `setVirtualHIDProfileOverride` and `resetVirtualHIDProfileOverride`.
public struct VirtualHIDProfileOverrideResult: Codable, Equatable, Sendable {
  /// The override the request asked for; nil for a reset or an unknown profile identifier.
  public let requested: VirtualHIDProfileID?
  /// The profile the controller publishes after the request; nil when none is live.
  public let live: VirtualHIDProfileID?
  /// How the live profile was selected: `automatic`, `override`, or `automatic-after-rejecting`.
  /// With no live profile, `override` when virtual output is disabled and the model has a stored
  /// override, else `automatic`.
  public let source: String
  public let failure: VirtualHIDProfileOverrideFailure?

  public init(
    requested: VirtualHIDProfileID?,
    live: VirtualHIDProfileID?,
    source: String,
    failure: VirtualHIDProfileOverrideFailure?
  ) {
    self.requested = requested
    self.live = live
    self.source = source
    self.failure = failure
  }

  public var succeeded: Bool { failure == nil }
}

/// One controller's virtual HID profile, reported in ``ApplicationServiceDeviceDescription``.
public struct ApplicationServiceVirtualHIDProfileStatus: Codable, Equatable, Sendable {
  /// The selected profile; nil before selection, when output is disabled, or when unavailable.
  public let profile: VirtualHIDProfileID?
  /// How `profile` was selected: `automatic`, `override`, or `automatic-after-rejecting`; nil
  /// when no profile is selected.
  public let source: String?
  /// The stored Advanced override in effect for this controller: its unit's, else its model's;
  /// nil when it selects automatically.
  public let override: VirtualHIDProfileID?
  /// Whose override `override` is: `unit` or `model`; nil without an override.
  public let overrideScope: String?
  /// Whether no virtual profile can represent the controller's declared controls.
  public let unavailable: Bool

  public init(
    profile: VirtualHIDProfileID?,
    source: String?,
    override: VirtualHIDProfileID?,
    overrideScope: String? = nil,
    unavailable: Bool
  ) {
    self.profile = profile
    self.source = source
    self.override = override
    self.overrideScope = overrideScope
    self.unavailable = unavailable
  }
}

extension VirtualHIDProfileOverrideError {
  /// The description reported as `virtualHIDProfileOverrideError` in service status.
  public var statusDescription: String {
    switch self {
    case .unreadableDirectory(let reason): "unreadable-directory: \(reason)"
    }
  }
}

extension VirtualHIDProfileSelector.Selection.Source {
  /// The wire name reported in status and override results.
  public var wireName: String {
    switch self {
    case .automatic: "automatic"
    case .override: "override"
    case .automaticAfterRejecting: "automatic-after-rejecting"
    }
  }
}
