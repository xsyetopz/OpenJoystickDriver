import Foundation
import OpenJoystickDriverKit

/// A controller that a profile can be created for: a connected controller, or a controller
/// model that is not connected. `ojd profile create --controller` accepts both.
struct ProfileControllerChoice: Equatable, Identifiable {
  /// Where the picker lists the choice.
  enum Group: Hashable {
    /// Connected controllers.
    case connected
    /// Controllers of existing profiles.
    case profiles
    /// A catalog model, under its protocol family. Each family is its own section, titled with
    /// the family's display name, so a Steam Deck model is not listed under the Steam Controller
    /// and two families whose names read alike in a language stay apart.
    case family(PhysicalProtocolID)
  }

  /// The identifier of the choice in the picker.
  let id: String
  /// The controller's own name; nil for a model that is not connected.
  let name: String?
  /// The vendor ID.
  let vendorID: UInt16
  /// The product ID.
  let productID: UInt16
  /// The model's protocol family, when the catalog has the model.
  let family: PhysicalProtocolID?
  /// The group of the picker that lists the choice.
  let group: Group

  /// The display name of the model's protocol family, when the catalog has the model.
  var familyName: String? { family?.displayName }

  /// The vendor and product ID.
  var model: ControllerModelID { ControllerModelID(vendorID: vendorID, productID: productID) }

  /// The name in the picker: the controller's name, else the identifiers of the model, with the
  /// family unless the picker section names it.
  ///
  /// The catalog has no product names.
  var label: String {
    if let name = OJDValue.reported(name).textOrNil { return name }
    let identifiers = OJDValue.usbIdentifier(vendorID: vendorID, productID: productID).displayText
    if case .family = group { return identifiers }
    return familyName.map { "\($0) · \(identifiers)" } ?? identifiers
  }

  /// The connected controllers, then the models that none of them has: first those of `profiles`,
  /// then those of `catalog`, which maps each catalog model to its protocol family.
  ///
  /// Models are ordered by vendor and product; catalog models by family display name first, then by
  /// family, so each family's models stay together when two family names read alike.
  static func choices(
    devices: [ApplicationServiceDeviceDescription],
    profiles: [RemappingProfile],
    catalog: [ControllerModelID: PhysicalProtocolID]
  ) -> [Self] {
    let connected = devices.map {
      Self(
        id: $0.sessionToken.rawValue,
        name: $0.name,
        vendorID: $0.vendorID,
        productID: $0.productID,
        family: catalog[ControllerModelID(vendorID: $0.vendorID, productID: $0.productID)],
        group: .connected
      )
    }
    var seen = Set(connected.map(\.model))
    func models(_ entries: [(model: ControllerModelID, group: Group)]) -> [Self] {
      entries.sorted { $0.model < $1.model }.compactMap { model, group in
        guard seen.insert(model).inserted else { return nil }
        return Self(
          id: String(format: "model-%04X-%04X", model.vendorID, model.productID),
          name: nil,
          vendorID: model.vendorID,
          productID: model.productID,
          family: catalog[model],
          group: group
        )
      }
    }
    let known = models(
      profiles.map {
        (ControllerModelID(vendorID: $0.device.vendorID, productID: $0.device.productID), .profiles)
      }
    )
    let catalogModels = models(catalog.map { ($0.key, .family($0.value)) })
    let ordered = catalogModels.sorted { left, right in
      let leftFamily = left.familyName ?? ""
      let rightFamily = right.familyName ?? ""
      if leftFamily != rightFamily {
        return leftFamily.localizedStandardCompare(rightFamily) == .orderedAscending
      }
      if left.family != right.family {
        return (left.family?.rawValue ?? "") < (right.family?.rawValue ?? "")
      }
      return (left.vendorID, left.productID) < (right.vendorID, right.productID)
    }
    return connected + known + ordered
  }
}

/// A titled run of choices in the picker.
struct ProfileControllerGroup: Equatable, Identifiable {
  /// The group.
  let group: ProfileControllerChoice.Group
  /// The title of the section.
  let title: String
  /// The choices in the section.
  let choices: [ProfileControllerChoice]
  /// The group itself.
  var id: ProfileControllerChoice.Group { group }

  /// The title of the section of `group`: the family's display name for a catalog family.
  static func title(of group: ProfileControllerChoice.Group) -> String {
    switch group {
    case .connected: OJDLocalized.string("ui.settings.notifications.controllerConnectedShort")
    case .profiles: OJDLocalized.string("ui.profiles.controllersOfProfiles")
    case .family(let family): family.displayName
    }
  }

  /// The sections of `choices`, in their order: connected controllers, controllers of existing
  /// profiles, then one section per protocol family.
  ///
  /// A section is keyed by its group, so two families whose `title` reads the same stay in sections
  /// of their own.
  static func sections(
    of choices: [ProfileControllerChoice],
    title: (ProfileControllerChoice.Group) -> String = title(of:)
  ) -> [Self] {
    var sections: [Self] = []
    for choice in choices {
      if let last = sections.last, last.group == choice.group {
        sections[sections.count - 1] = Self(
          group: last.group,
          title: last.title,
          choices: last.choices + [choice]
        )
      } else {
        sections.append(Self(group: choice.group, title: title(choice.group), choices: [choice]))
      }
    }
    return sections
  }
}

/// What the profile creation sheet knows besides the fields: the controllers it offers, the
/// profiles that already exist, and the state of the catalog read.
struct ProfileCreationContext: Equatable {
  /// The controllers the sheet offers.
  let choices: [ProfileControllerChoice]
  /// The existing profiles.
  let profiles: [RemappingProfile]
  /// Whether the catalog is still being read; its models are not offered yet.
  var isLoadingCatalog = false
  /// How many user controller record files could not be read.
  var unreadableRecordFiles = 0

  /// The sections of the picker.
  var sections: [ProfileControllerGroup] { ProfileControllerGroup.sections(of: choices) }
}

/// The names profiles can have among `profiles`.
enum ProfileNaming {
  /// Whether another profile has `name`, compared as the profile library compares names.
  static func isTaken(_ name: String, in profiles: [RemappingProfile]) -> Bool {
    let key = RemappingProfile.normalizedName(ProfileNameValidation.trimmedName(name))
    return profiles.contains { RemappingProfile.normalizedName($0.name) == key }
  }

  /// `base`, or `base 2`, `base 3` and so on for the first name no profile has.
  ///
  /// An empty base stays empty.
  static func availableName(_ base: String, in profiles: [RemappingProfile]) -> String {
    guard !base.isEmpty, isTaken(base, in: profiles) else { return base }
    var number = 2
    while isTaken("\(base) \(number)", in: profiles) { number += 1 }
    return "\(base) \(number)"
  }
}

/// What a new profile starts from.
enum ProfileCreationTemplate: Equatable {
  /// An empty profile.
  case empty
  /// Gyro motion drives a stick of the virtual gamepad.
  case gyroStick
}

/// The edits made in the profile creation sheet.
///
/// The controller is the first connected one until the person picks; a pick stays on its model when
/// the controller disconnects, and there is no controller when no choice has that model. The name
/// is the typed one, else the controller's name as the picker showed it.
struct ProfileCreationFields: Equatable {
  /// The name the person typed, or nil before an edit.
  var editedName: String?
  /// The choice the person picked, as the picker showed it.
  var picked: ProfileControllerChoice?
  /// Whether the profile applies to every app or to one app.
  var scopeKind = ProfileScopeKind.global
  /// The identifier of the app when the profile applies to one app.
  var appID = ""
  /// The output policy `ojd profile create` starts with.
  var outputPolicy = RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared)
  /// What the profile starts from.
  var template = ProfileCreationTemplate.empty
  /// The stick that the gyro-stick template drives.
  var gyroStick = RemappingGyroStickTemplate.Stick.right

  /// Whether the template needs a motion sensor that the controller lacks.
  func lacksMotion(in context: ProfileCreationContext) -> Bool {
    guard template == .gyroStick, let controller = controller(in: context) else { return false }
    return
      !(ProtocolDriverRegistry().profileCapabilities(for: controller.model)?.physicalInput
      .motion ?? false)
  }

  /// The controller the profile belongs to; nil while none is picked and none is connected, or
  /// when the picked model is not offered.
  func controller(in context: ProfileCreationContext) -> ProfileControllerChoice? {
    guard let picked else { return context.choices.first { $0.group == .connected } }
    return context.choices.first { $0.id == picked.id }
      ?? context.choices.first { $0.model == picked.model }
  }

  /// The name field: the typed name, else the controller's name made free of existing names;
  /// empty when the controller has no name.
  func name(in context: ProfileCreationContext) -> String {
    editedName
      ?? ProfileNaming.availableName(
        Self.controllerName(picked ?? controller(in: context)),
        in: context.profiles
      )
  }

  /// Returns the trimmed name of `choice`, or empty when it has none.
  static func controllerName(_ choice: ProfileControllerChoice?) -> String {
    choice?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  /// Returns whether another profile has the name in the name field.
  func isNameTaken(in context: ProfileCreationContext) -> Bool {
    ProfileNaming.isTaken(name(in: context), in: context.profiles)
  }

  /// The profile these fields describe, or nil while a field is missing or invalid or the name is
  /// taken.
  func proposedProfile(in context: ProfileCreationContext) -> RemappingProfile? {
    guard let controller = controller(in: context), !isNameTaken(in: context) else { return nil }
    let applicationScope: RemappingApplicationScope
    switch scopeKind {
    case .global: applicationScope = .global
    case .application: applicationScope = .application(appID: appID)
    }
    let device = RemappingDeviceScope(
      vendorID: controller.vendorID,
      productID: controller.productID
    )
    let trimmedName = ProfileNameValidation.trimmedName(name(in: context))
    let profile: RemappingProfile
    switch template {
    case .empty:
      profile = RemappingProfile(
        name: trimmedName,
        device: device,
        applicationScope: applicationScope,
        outputPolicy: outputPolicy,
        bindings: []
      )
    case .gyroStick:
      guard
        let made = try? RemappingGyroStickTemplate.profile(
          name: trimmedName,
          device: device,
          applicationScope: applicationScope,
          stick: gyroStick,
          activation: nil,
          capabilities: ProtocolDriverRegistry().profileCapabilities(for: controller.model)
            ?? .unknown
        )
      else { return nil }
      profile = made
    }
    guard (try? profile.validate()) != nil else { return nil }
    return profile
  }

  /// Whether the sheet shows its validation message: the fields differ from the defaults and do
  /// not make a valid profile.
  func showsValidation(isValid: Bool) -> Bool { !isValid && self != Self() }
}
