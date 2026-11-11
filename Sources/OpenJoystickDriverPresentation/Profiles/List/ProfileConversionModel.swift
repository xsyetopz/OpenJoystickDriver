import Foundation
import OpenJoystickDriverKit

/// The edits of the Convert sheet: the target model and the name of the converted profile.
///
/// The target is the picked model, else the first offered model that is not the source's. A pick
/// stays on its model when its controller disconnects, and there is no target when no choice has
/// that model.
struct ProfileConversionModel: Equatable {
  /// The profile to convert.
  let source: RemappingProfile
  /// The controllers and models the sheet offers.
  var choices: [ProfileControllerChoice]
  /// The existing profiles, whose names the converted profile must not take.
  var profiles: [RemappingProfile]
  /// The choice the person picked, as the picker showed it.
  var picked: ProfileControllerChoice?
  /// The name the person typed, or nil before an edit.
  var editedName: String?

  /// Creates the model for `source`.
  init(source: RemappingProfile, choices: [ProfileControllerChoice], profiles: [RemappingProfile]) {
    self.source = source
    self.choices = choices
    self.profiles = profiles
  }

  /// The model that the conversion targets, or nil.
  var target: ProfileControllerChoice? {
    guard let picked else {
      let own = ControllerModelID(
        vendorID: source.device.vendorID,
        productID: source.device.productID
      )
      return choices.first { $0.model != own } ?? choices.first
    }
    return choices.first { $0.id == picked.id } ?? choices.first { $0.model == picked.model }
  }

  /// The name field: the typed name, else the source's name followed by the target's identifiers,
  /// made free of existing names; empty without a target.
  var name: String {
    if let editedName { return editedName }
    guard let target else { return "" }
    return ProfileNaming.availableName(
      "\(source.name) \(Self.identity(of: target.model))",
      in: profiles
    )
  }

  /// Whether another profile has the name in the field.
  var isNameTaken: Bool { ProfileNaming.isTaken(name, in: profiles) }

  /// Returns the vendor and product ID as `VVVV:PPPP`.
  static func identity(of model: ControllerModelID) -> String {
    unsafe String(format: "%04X:%04X", model.vendorID, model.productID)
  }

  /// Returns the conversion for the target and name, or nil when there is no target, the name is
  /// taken or blank, or the converted profile is not valid.
  ///
  /// - Parameter capabilities: Returns what a model reports, or nil for an unknown model.
  /// - Returns: The conversion for the target and name, or nil when there is no target, the name is
  ///   taken or blank, or the converted profile is not valid.
  func converted(
    capabilities: (ControllerModelID) -> ControllerProfileCapabilities? = {
      ProtocolDriverRegistry().profileCapabilities(for: $0)
    }
  ) -> RemappingProfileConversion? {
    let trimmed = ProfileNameValidation.trimmedName(name)
    guard let target, !trimmed.isEmpty, !isNameTaken else { return nil }
    let conversion = RemappingProfileConversion(
      converting: source,
      to: RemappingDeviceScope(vendorID: target.vendorID, productID: target.productID),
      name: trimmed,
      capabilities: capabilities(target.model) ?? .unknown
    )
    return (try? conversion.profile.validate()) == nil ? nil : conversion
  }
}

/// What a finished conversion tells the person: the new profile, its target and each part left out.
struct ProfileConversionReport: Identifiable, Equatable {
  /// The identifier of the new profile.
  let id: UUID
  /// The name of the new profile.
  let profileName: String
  /// The target controller as `VVVV:PPPP`.
  let identity: String
  /// One line per part left out; empty when the target took everything.
  let lines: [String]

  /// Creates the report of `conversion`.
  init(_ conversion: RemappingProfileConversion) {
    let device = conversion.profile.device
    id = conversion.profile.id
    profileName = conversion.profile.name
    identity = ProfileConversionModel.identity(
      of: ControllerModelID(vendorID: device.vendorID, productID: device.productID)
    )
    lines = conversion.leftOut.map { part in
      let suffix = part.section.localizationSuffix
      let section = OJDLocalized.string("ui.profiles.convert.section.\(suffix)")
      guard !part.sources.isEmpty else {
        return OJDLocalized.formatted("ui.profiles.convert.leftOutPart", section)
      }
      return OJDLocalized.formatted(
        "ui.profiles.convert.leftOut",
        section,
        part.sources.map(RuntimePresentation.sourceLabel).joined(separator: ", ")
      )
    }
  }
}

extension RemappingProfileConversion.LeftOut.Section {
  /// The last part of the localization key that names the section.
  var localizationSuffix: String { String(rawValue.prefix(1)).lowercased() + rawValue.dropFirst() }
}
