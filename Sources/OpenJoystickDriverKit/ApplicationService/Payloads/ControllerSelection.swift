/// A connected controller named by a runtime or unit ID, or by its `VVVV:PPPP` model.
public enum ControllerSelection: Equatable, Hashable, Sendable {
  case id(String)
  case model(vendorID: UInt16, productID: UInt16)

  /// `VVVV:PPPP` as a model, and other nonempty text as an ID.
  public init?(_ text: String) {
    guard !text.isEmpty else { return nil }
    self =
      Self.model(text).map { .model(vendorID: $0.vendorID, productID: $0.productID) } ?? .id(text)
  }

  /// `VVVV:PPPP`, four hex digits each, case-insensitive.
  public static func model(_ text: String) -> (vendorID: UInt16, productID: UInt16)? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, parts.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isHexDigit) }),
      let vendorID = UInt16(parts[0], radix: 16), let productID = UInt16(parts[1], radix: 16)
    else { return nil }
    return (vendorID, productID)
  }

  /// The devices that this selection names, in the order of `devices`.
  public func matches(
    in devices: [ApplicationServiceDeviceDescription]
  ) -> [ApplicationServiceDeviceDescription] {
    switch self {
    case .id(let id):
      devices.filter { $0.runtimeIdentifier == id || $0.unitIdentifier == id }
    case .model(let vendorID, let productID):
      devices.filter { $0.vendorID == vendorID && $0.productID == productID }
    }
  }
}
