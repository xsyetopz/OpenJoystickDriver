import Foundation

/// Selects the motion source for an explicitly paired left/right Joy-Con session.
public enum RemappingJoyConGyroSelection: String, Codable, CaseIterable, Sendable {
  /// No Joy-Con supplies motion.
  case disabled = "Disabled"
  /// The left Joy-Con supplies motion.
  case left = "Left"
  /// The right Joy-Con supplies motion.
  case right = "Right"
}

/// Profile behavior used only after two exact runtime Joy-Con identities are paired.
public struct RemappingJoyConPairSettings: Codable, Equatable, Sendable {
  /// Joy-Con that supplies motion for the pair.
  public let gyroSelection: RemappingJoyConGyroSelection

  /// Creates pair settings.
  public init(gyroSelection: RemappingJoyConGyroSelection = .right) {
    self.gyroSelection = gyroSelection
  }

  /// Profile document keys of the pair settings.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case gyroSelection
  }

  /// Decodes pair settings from a profile document, which must give the gyro selection.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    gyroSelection = try values.decode(RemappingJoyConGyroSelection.self, forKey: .gyroSelection)
  }
}

/// The side of a Joy-Con half that a paired session accepts, from the `JoyConLeft` and
/// `JoyConRight` layouts of the current controller records.
public enum JoyConHalf: Equatable, Sendable {
  /// The left half.
  case left
  /// The right half.
  case right

  /// Creates the half that the controller record of a vendor and product ID describes.
  ///
  /// Returns `nil` when the record is missing or its layout is neither Joy-Con half.
  public init?(vendorID: UInt16, productID: UInt16) {
    let layout =
      DeviceCatalog.current.withLock { $0 }
      .record(for: ControllerModelID(vendorID: vendorID, productID: productID))?.parameters.layout
    switch layout {
    case .joyConLeft: self = .left
    case .joyConRight: self = .right
    default: return nil
    }
  }

  /// Lists a left-half product ID followed by the right halves of its generation.
  ///
  /// The right halves are the records of the same vendor and the same Switch 2 membership. Empty
  /// when no record declares a left half.
  public static func generationProductIDs(forLeft productID: UInt16) -> [UInt16] {
    let catalog = DeviceCatalog.current.withLock { $0 }
    let halves = catalog.hidModels.compactMap { model in
      catalog.record(for: model).map {
        (model: model, protocolID: $0.physicalProtocolID, layout: $0.parameters.layout)
      }
    }
    let lefts = halves.filter {
      $0.model.productID == productID && $0.layout == .joyConLeft
    }
    guard !lefts.isEmpty else { return [] }
    let rights = halves.filter { right in
      right.layout == .joyConRight
        && lefts.contains {
          $0.model.vendorID == right.model.vendorID
            && $0.protocolID == right.protocolID
        }
    }
    return [productID] + rights.map(\.model.productID)
  }
}
