#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that converts a profile to another controller model: the target among the connected
  /// controllers and the known models, and the name of the converted profile.
  struct ProfileConversionSheet: View {
    /// The profile to convert.
    let source: RemappingProfile
    /// The controllers and models to offer.
    let choices: [ProfileControllerChoice]
    /// The existing profiles, whose names the converted profile must not take.
    let profiles: [RemappingProfile]
    /// Whether the catalog is still being read.
    let isLoadingCatalog: Bool
    /// Receives the conversion when the person chooses Convert.
    let onConvert: (RemappingProfileConversion) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The picked target and the typed name.
    @State
    private var picks = ProfileConversionPicks()

    /// The target picker, the name field and the Cancel and Convert buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("action.convert")).font(.headline)
        Form {
          Picker(OJDLocalized.string("term.controller"), selection: targetBinding) {
            ForEach(ProfileControllerGroup.sections(of: model.choices)) { section in
              Section(header: Text(section.title)) {
                ForEach(section.choices) { choice in Text(choice.label).tag(choice.id) }
              }
            }
          }.ojdAccessibilityLabel(OJDLocalized.string("term.controller"))
          if isLoadingCatalog { ProgressView().controlSize(.small) }
          TextField(OJDLocalized.string("term.profileName"), text: nameBinding)
            .ojdAccessibilityLabel(OJDLocalized.string("term.profileName"))
          if model.isNameTaken {
            Text(OJDLocalized.string("ui.error.duplicateProfile"))
              .foregroundColor(Color(NSColor.systemRed))
          } else if !model.name.isEmpty,
            ProfileNameValidation.trimmedName(model.name).isEmpty
          {
            Text(OJDLocalized.string("ui.capture.profileNameValidation"))
              .foregroundColor(Color(NSColor.systemRed))
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("action.convert")) {
            guard let conversion else { return }
            onConvert(conversion)
            presentationMode.wrappedValue.dismiss()
          }.disabled(conversion == nil)
        }
      }.ojdSheet(.compact)
    }

    /// The model of the sheet's edits.
    private var model: ProfileConversionModel {
      var edits = ProfileConversionModel(source: source, choices: choices, profiles: profiles)
      edits.picked = picks.picked
      edits.editedName = picks.editedName
      return edits
    }

    /// The conversion the fields describe, or nil.
    private var conversion: RemappingProfileConversion? { model.converted() }

    /// The target picker's binding to the identifier of the choice.
    private var targetBinding: Binding<String> {
      Binding(
        get: { model.target?.id ?? "" },
        set: { id in picks.picked = choices.first { $0.id == id } }
      )
    }

    /// The name field's binding.
    private var nameBinding: Binding<String> {
      Binding(get: { model.name }, set: { picks.editedName = $0 })
    }
  }

  /// What the person picked and typed in the Convert sheet.
  private struct ProfileConversionPicks {
    /// The choice the person picked.
    var picked: ProfileControllerChoice?
    /// The name the person typed, or nil before an edit.
    var editedName: String?
  }

  /// The sheet that lists what a conversion left out.
  struct ProfileConversionReportSheet: View {
    /// What the conversion left out.
    let report: ProfileConversionReport
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode

    /// The result line, the parts left out and the Done button.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(
          OJDLocalized.formatted(
            "ui.profiles.convert.done",
            report.profileName,
            report.identity
          )
        ).font(.headline).fixedSize(horizontal: false, vertical: true)
        if report.lines.isEmpty {
          Text(OJDLocalized.string("ui.profiles.convert.nothingLeftOut"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        } else {
          Text(OJDLocalized.string("ui.profiles.convert.leftOutHeading"))
          VStack(alignment: .leading, spacing: OJDSpacing.small) {
            ForEach(report.lines, id: \.self) { line in
              Text(line).fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.done")) {
            presentationMode.wrappedValue.dismiss()
          }.keyboardShortcut(.defaultAction)
        }
      }.ojdSheet(.compact)
    }
  }

#endif
