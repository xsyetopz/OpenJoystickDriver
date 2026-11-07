import Foundation

extension ControllerRecordDraft {
  /// Why a record cannot be drafted from the SDL_GameControllerDB line of a controller.
  public enum SDLFailure: Error, Equatable, Sendable {
    /// The model has a bundled record, so the connect-time conversion is not what drives it.
    case hasRecord
    /// No interface of the device satisfies the `HIDDescriptor` contract, with the rule the first
    /// interface violates; the contract is what lets the converted map bind.
    case descriptorContract(HIDDescriptorContract.Violation)
    /// The database has no line for the device; the GUID searched, or nil without a USB identity.
    case noLine(guid: String?)
    /// A line matched but cannot drive the device, with the reason.
    case rejected(String)
  }

  /// Drafts a `Controller` record from the SDL_GameControllerDB line of `device`, converted
  /// against the elements of its HID interface.
  ///
  /// The record names the `HIDDescriptor` family and the converted `input.hidUsageMap`, which is
  /// what the pad runs at connect time when no record exists. Nothing is captured, so the report
  /// fields are empty.
  public init(model: ControllerModelID, sdlDevice device: PhysicalDevice) throws(SDLFailure) {
    try self.init(model: model, device: device, database: .bundled)
  }

  /// ``init(model:sdlDevice:)`` with the lines of `database`.
  init(
    model: ControllerModelID,
    device: PhysicalDevice,
    database: SDLGameControllerDatabase
  ) throws(SDLFailure) {
    guard ControllerRecordSet.bundled.records[model] == nil else { throw .hasRecord }
    let interfaces = device.interfaces ?? []
    let violations = interfaces.map { HIDDescriptorContract.violation(in: $0.hidLayout) }
    guard let index = violations.firstIndex(of: nil) else {
      throw .descriptorContract(violations.first.flatMap { $0 } ?? .missingDescriptor)
    }
    guard let line = database.match(for: device) else {
      throw .noLine(guid: SDLGameControllerDatabase.guid(of: device)?.description)
    }
    let converted: SDLConvertedMapping
    do throws(SDLMappingRejection) {
      converted = try SDLMappingConverter.convert(
        fields: line.fields,
        elements: interfaces[index].hidLayout?.elements ?? []
      )
    } catch {
      throw .rejected(error.reason)
    }
    let document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version,
      "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID),
      "productID": Int(model.productID),
      "modes": [
        ["id": "default", "protocol": ["family": PhysicalProtocolID.hidDescriptor.rawValue]]
      ],
      "input": ["hidUsageMap": converted.usageMap.json],
    ]
    guard let json = try? OrderedJSON(foundation: document, order: .recordKeys) else {
      throw .rejected("the record cannot be written")
    }
    operation = .add
    family = .hidDescriptor
    reportID = nil
    reportLength = nil
    capturedReports = 0
    changedBytes = []
    text = json.formatted()
  }
}

extension ControllerRecordDraft.SDLFailure {
  /// The message for the failure.
  ///
  /// - Parameters:
  ///   - identity: The vendor and product ID of the controller.
  ///   - localize: Returns the localized format for a key of the en-US catalog.
  /// - Returns: The message in the language `localize` uses.
  public func message(identity: String, localize: (String) -> String) -> String {
    switch self {
    case .hasRecord:
      String(format: localize("cli.record.draft.sdl.hasRecord"), identity)
    case .descriptorContract(let violation):
      String(format: localize("cli.record.draft.sdl.contract"), identity, violation.rawValue)
    case .noLine(let guid):
      String(format: localize("cli.record.draft.sdl.noLine"), identity, guid ?? "")
    case .rejected(let reason):
      String(format: localize("cli.record.draft.sdl.rejected"), identity, reason)
    }
  }
}
