#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that creates a profile: its name, controller, target app and output policy.
  struct ProfileNameSheet: View {
    /// The title of the sheet.
    let title: String
    /// What the sheet offers.
    let context: ProfileCreationContext
    /// Receives the profile when the person chooses Create.
    let onCreate: (RemappingProfile) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The edits of the sheet.
    @State
    private var fields = ProfileCreationFields()

    /// The name, controller, target app and output policy fields and the Cancel and Create buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(title).font(.headline)
        Form {
          if context.choices.isEmpty {
            if context.isLoadingCatalog {
              ProgressView().controlSize(.small)
            } else {
              Text(OJDLocalized.string("status.connectController"))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
          } else {
            TextField(OJDLocalized.string("term.profileName"), text: nameBinding)
              .ojdAccessibilityLabel(OJDLocalized.string("term.profileName"))
            if let message = nameProblem {
              Text(message).foregroundColor(Color(NSColor.systemRed)).fixedSize(
                horizontal: false,
                vertical: true
              )
            }
            Picker(OJDLocalized.string("term.controller"), selection: controllerBinding) {
              ForEach(context.sections) { section in
                Section(header: Text(section.title)) {
                  ForEach(section.choices) { choice in Text(choice.label).tag(choice.id) }
                }
              }
            }.ojdAccessibilityLabel(OJDLocalized.string("term.controller"))
            if context.isLoadingCatalog {
              ProgressView().controlSize(.small)
            }
            if fields.controller(in: context) == nil {
              Text(OJDLocalized.string("ui.profiles.chooseController"))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            if context.unreadableRecordFiles > 0 {
              Text(
                OJDLocalized.formatted(
                  "ui.profiles.unreadableRecords",
                  OJDLocalized.string("ui.sidebar.library.title")
                )
              )
              .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Picker(OJDLocalized.string("ui.profiles.target"), selection: $fields.scopeKind) {
              Text(OJDLocalized.string("ui.profiles.targetGlobal")).tag(ProfileScopeKind.global)
              Text(OJDLocalized.string("ui.profiles.targetApplication")).tag(
                ProfileScopeKind.application
              )
            }.ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.target"))
            if fields.scopeKind == .application {
              ProfileAppChooser(appIDs: $fields.appIDs)
            }
            Picker(OJDLocalized.string("ui.profiles.template"), selection: $fields.template) {
              Text(OJDLocalized.string("ui.profiles.templateEmpty"))
                .tag(ProfileCreationTemplate.empty)
              Text(OJDLocalized.string("ui.profiles.templateGyroStick"))
                .tag(ProfileCreationTemplate.gyroStick)
            }.ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.template"))
            if fields.template == .gyroStick {
              Picker(OJDLocalized.string("ui.profiles.gyro.output"), selection: $fields.gyroStick) {
                Text(OJDLocalized.string("ui.profiles.gyro.leftStick")).tag(
                  RemappingGyroStickTemplate.Stick.left
                )
                Text(OJDLocalized.string("ui.profiles.gyro.rightStick")).tag(
                  RemappingGyroStickTemplate.Stick.right
                )
              }.ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.gyro.output"))
              if fields.lacksMotion(in: context), let controller = fields.controller(in: context) {
                Text(
                  OJDLocalized.formatted("ui.profiles.templateNoMotion", controller.label)
                ).foregroundColor(Color(NSColor.systemRed))
              }
            }
            if fields.template == .empty {
              ProfileOutputPolicyView(policy: fields.outputPolicy) { fields.outputPolicy = $0 }
            }
            if fields.showsValidation(isValid: proposedProfile != nil) && nameProblem == nil {
              Text(OJDLocalized.string("ui.profiles.creationValidation"))
                .foregroundColor(Color(NSColor.systemRed)).fixedSize(
                  horizontal: false,
                  vertical: true
                )
            }
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("action.create")) {
            guard let proposedProfile else { return }
            onCreate(proposedProfile)
            presentationMode.wrappedValue.dismiss()
          }.disabled(proposedProfile == nil)
        }
      }.padding(20).frame(width: 420)
    }

    /// The profile the fields describe, or nil.
    private var proposedProfile: RemappingProfile? { fields.proposedProfile(in: context) }

    /// The message about the name in the name field: a name another profile has, or one that is
    /// empty once trimmed; nil when the name is acceptable.
    private var nameProblem: String? {
      let name = fields.name(in: context)
      if fields.isNameTaken(in: context) { return OJDLocalized.string("ui.error.duplicateProfile") }
      if !name.isEmpty && ProfileNameValidation.trimmedName(name).isEmpty {
        return OJDLocalized.string("ui.capture.profileNameValidation")
      }
      return nil
    }

    /// The name field's binding; typing sets the edited name.
    private var nameBinding: Binding<String> {
      Binding(
        get: { fields.name(in: context) },
        set: { fields.editedName = $0 }
      )
    }

    /// The controller picker's binding to the identifier of the choice.
    private var controllerBinding: Binding<String> {
      Binding(
        get: { fields.controller(in: context)?.id ?? "" },
        set: { id in fields.picked = context.choices.first { $0.id == id } }
      )
    }
  }

  /// The sheet that asks for the name of a copy of a profile; the name starts as the default copy
  /// name.
  struct ProfileDuplicateSheet: View {
    /// The profile to copy.
    let source: RemappingProfile
    /// The existing profiles, whose names the copy must not take.
    let profiles: [RemappingProfile]
    /// Receives the copy when the person chooses Duplicate.
    let onDuplicate: (RemappingProfile) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The name the person typed, or nil before an edit.
    @State
    private var name: String?

    /// The name field and the Cancel and Duplicate buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("action.duplicate")).font(.headline)
        Form {
          TextField(OJDLocalized.string("term.profileName"), text: nameBinding)
            .ojdAccessibilityLabel(OJDLocalized.string("term.profileName"))
          if ProfileNaming.isTaken(shownName, in: profiles) {
            Text(OJDLocalized.string("ui.error.duplicateProfile"))
              .foregroundColor(Color(NSColor.systemRed))
          } else if !shownName.isEmpty && ProfileNameValidation.trimmedName(shownName).isEmpty {
            Text(OJDLocalized.string("ui.capture.profileNameValidation"))
              .foregroundColor(Color(NSColor.systemRed))
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("action.duplicate")) {
            guard let duplicate else { return }
            onDuplicate(duplicate)
            presentationMode.wrappedValue.dismiss()
          }.disabled(duplicate == nil)
        }
      }.padding(20).frame(width: 420)
    }

    /// The name in the field.
    private var shownName: String { name ?? defaultDuplicateName(of: source, in: profiles) }

    /// The name field's binding.
    private var nameBinding: Binding<String> {
      Binding(get: { shownName }, set: { name = $0 })
    }

    /// The copy under the name in the field, or nil when the name is not acceptable.
    private var duplicate: RemappingProfile? {
      duplicatedProfile(source, named: shownName, in: profiles)
    }
  }

#endif
