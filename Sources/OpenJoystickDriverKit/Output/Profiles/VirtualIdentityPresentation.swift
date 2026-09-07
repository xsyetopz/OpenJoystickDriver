import Foundation

/// Control-glyph and system-symbol family for a published virtual identity.
public enum VirtualIdentityGlyphFamily: String, Codable, CaseIterable, Sendable {
  case xbox
  case playstation
  case nintendo
  case steam
  case generic
}

/// SF Symbol and glyph family owned by the published USB product, not the physical pad.
public struct VirtualIdentityPresentation: Equatable, Hashable, Sendable {
  public let glyphFamily: VirtualIdentityGlyphFamily
  public let controllerSymbolName: String
  public let controllerSymbolFallback: String

  public init(
    glyphFamily: VirtualIdentityGlyphFamily,
    controllerSymbolName: String,
    controllerSymbolFallback: String = "gamecontroller"
  ) {
    self.glyphFamily = glyphFamily
    self.controllerSymbolName = controllerSymbolName
    self.controllerSymbolFallback = controllerSymbolFallback
  }

  public static let xbox = Self(glyphFamily: .xbox, controllerSymbolName: "xbox.logo")
  public static let playstation = Self(
    glyphFamily: .playstation,
    controllerSymbolName: "playstation.logo"
  )
  public static let nintendo = Self(glyphFamily: .nintendo, controllerSymbolName: "gamecontroller")
  public static let steam = Self(glyphFamily: .steam, controllerSymbolName: "gamecontroller")
  public static let generic = Self(glyphFamily: .generic, controllerSymbolName: "gamecontroller")

  public static func forProfile(_ profile: VirtualDeviceProfile) -> Self {
    switch (profile.vendorID, profile.productID) {
    case (0x045E, _): return .xbox
    case (0x054C, _): return .playstation
    case (0x057E, _): return .nintendo
    case (0x28DE, _): return .steam
    default: break
    }
    let name = profile.productName.lowercased()
    if name.contains("xbox") { return .xbox }
    if name.contains("dualshock") || name.contains("dualsense") || name.contains("playstation") {
      return .playstation
    }
    if name.contains("switch") || name.contains("nintendo") { return .nintendo }
    if name.contains("steam") { return .steam }
    return .generic
  }
}

extension VirtualDeviceProfile {
  public var presentation: VirtualIdentityPresentation {
    VirtualIdentityPresentation.forProfile(self)
  }

  /// Official USB product string plus published VID/PID, not the physical pad name.
  public var publishedUSBIdentityLabel: String {
    "\(productName) (\(String(format: "%04X:%04X", vendorID, productID)))"
  }
}

/// Resolves the USB identity actually published for a connected controller.
public enum PublishedVirtualIdentity {
  public static func profile(
    for device: ApplicationServiceDeviceDescription,
    requested requestedIdentity: CompatibilityIdentity
  ) -> VirtualDeviceProfile {
    let identity: CompatibilityIdentity
    if requestedIdentity != .automatic,
      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: requestedIdentity)
        .isAvailable
    {
      identity = requestedIdentity
    } else {
      identity = AutomaticCompatibilityResolver.resolve(for: device).identity
    }
    return CompatibilityOutputProfileCatalog.profile(for: identity).deviceProfile
  }

  public static func presentation(
    for device: ApplicationServiceDeviceDescription,
    requested requestedIdentity: CompatibilityIdentity
  ) -> VirtualIdentityPresentation {
    profile(for: device, requested: requestedIdentity).presentation
  }
}
