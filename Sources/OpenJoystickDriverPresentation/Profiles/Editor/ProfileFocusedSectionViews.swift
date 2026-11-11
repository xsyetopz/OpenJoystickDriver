#if canImport(SwiftUI)
  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Combinations section: the chords and sequences of the profile, each with an add button.
  struct ProfileCombinationsSection: View {
    /// The profile.
    let profile: RemappingProfile
    /// Opens a sheet.
    let openSheet: (ProfileEditorSheet) -> Void
    /// Removes the chord with the identifier.
    let removeChord: (UUID) -> Void
    /// Removes the sequence with the identifier.
    let removeSequence: (UUID) -> Void

    /// The chords and sequences.
    var body: some View {
      Group {
        combinationGroup(
          title: OJDLocalized.string("ui.profiles.chords"),
          addTitle: OJDLocalized.string("ui.profiles.addChord"),
          isEmpty: profile.chords.isEmpty,
          emptyMessage: OJDLocalized.string("ui.profiles.noChords"),
          add: { openSheet(.chord) },
          content: {
            ForEach(profile.chords) { chord in
              HStack {
                Text(
                  chord.sources.map(RuntimePresentation.sourceLabel).sorted().joined(
                    separator: " + "
                  )
                )
                OJDSystemSymbol(name: "arrow.right", fallback: "->").accessibilityHidden(true)
                KeyboardDestinationLabel(destination: chord.destination)
                Spacer()
                removeButton { removeChord(chord.id) }
              }
            }
          }
        )
        combinationGroup(
          title: OJDLocalized.string("ui.profiles.sequences"),
          addTitle: OJDLocalized.string("ui.profiles.addSequence"),
          isEmpty: profile.sequences.isEmpty,
          emptyMessage: OJDLocalized.string(
            "ui.profiles.noSequences"
          ),
          add: { openSheet(.sequence) },
          content: {
            ForEach(profile.sequences) { sequence in
              HStack {
                Text(
                  sequence.sources.map(RuntimePresentation.sourceLabel).joined(separator: " -> ")
                )
                Text(String(format: "(%.0f ms)", sequence.windowMs)).foregroundColor(
                  Color(NSColor.secondaryLabelColor)
                )
                OJDSystemSymbol(name: "arrow.right", fallback: "->").accessibilityHidden(true)
                KeyboardDestinationLabel(destination: sequence.destination)
                Spacer()
                removeButton { removeSequence(sequence.id) }
              }
            }
          }
        )
      }
    }

    /// A section with a title, an add button, and either `content` or the empty message.
    ///
    /// - Parameters:
    ///   - title: The section title.
    ///   - addTitle: The label of the add button.
    ///   - isEmpty: Whether there is nothing to list.
    ///   - emptyMessage: The text shown when empty.
    ///   - add: Called when the person chooses the add button.
    ///   - content: The rows.
    /// - Returns: The section.
    private func combinationGroup<Content: View>(
      title: String,
      addTitle: String,
      isEmpty: Bool,
      emptyMessage: String,
      add: @escaping () -> Void,
      @ViewBuilder content: () -> Content
    ) -> some View {
      Section(
        header: HStack {
          Text(title)
          Spacer()
          OJDCompactSymbolButton(symbolName: "plus", label: addTitle, action: add)
        }
      ) {
        if isEmpty {
          Text(emptyMessage).foregroundColor(Color(NSColor.secondaryLabelColor))
        } else {
          content()
        }
      }
    }
  }

  /// The Layers section: the layers of the profile and their assignments.
  struct ProfileLayersSection: View {
    /// The profile.
    let profile: RemappingProfile
    /// What the profile's controller has.
    let capabilities: ControllerProfileCapabilities
    /// Opens a sheet.
    let openSheet: (ProfileEditorSheet) -> Void
    /// Removes the layer with the identifier.
    let removeLayer: (UUID) -> Void
    /// Removes the assignment from the layer, by layer and assignment identifier.
    let removeBinding: (UUID, UUID) -> Void

    /// The layers section and the group of each layer.
    var body: some View {
      Section(
        header: HStack {
          Text(OJDLocalized.string("ui.profiles.layers"))
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "plus",
            label: OJDLocalized.string("ui.profiles.addLayer")
          ) { openSheet(.layer) }
        }
      ) {
        if profile.layers.isEmpty {
          Text(OJDLocalized.string("ui.profiles.noLayers"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
      }
      ForEach(profile.layers) { layer in layerGroup(layer) }
    }

    /// The section of one layer: its name and activator, buttons to add an assignment, edit motion
    /// and remove, and its assignments.
    private func layerGroup(_ layer: RemappingLayer) -> some View {
      Section(
        header: HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(layer.name)
            Text(layerDescription(layer)).font(.caption).foregroundColor(
              Color(NSColor.secondaryLabelColor)
            )
          }
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "plus",
            label: OJDLocalized.string("action.addAssignment")
          ) { openSheet(.layerBinding(layer)) }
          OJDCompactSymbolButton(
            symbolName: "pencil",
            label: OJDLocalized.string("ui.profiles.motion.title")
          ) { openSheet(.layerMotion(layer)) }.disabled(
            !capabilities.physicalInput.motion && layer.motionTuning == nil
          )
          removeButton { removeLayer(layer.id) }
        }
      ) {
        if layer.bindings.isEmpty {
          Text(OJDLocalized.string("ui.profiles.noAssignments"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        ForEach(layer.bindings) { binding in
          HStack {
            Text(RuntimePresentation.sourceLabel(binding.source))
            OJDSystemSymbol(name: "arrow.right", fallback: "->").accessibilityHidden(true)
            KeyboardDestinationLabel(destination: binding.destination)
            Spacer()
            if binding.axisTuning != nil {
              Button(OJDLocalized.string("action.adjust")) {
                openSheet(.layerAdjustment(layer.id, binding))
              }
            }
            Button(OJDLocalized.string("ui.profiles.behavior")) {
              openSheet(.layerBehavior(layer.id, binding))
            }
            removeButton { removeBinding(layer.id, binding.id) }
          }
        }
      }
    }

    /// Returns the layer's activation mode and activator in words.
    private func layerDescription(_ layer: RemappingLayer) -> String {
      let mode =
        layer.activationMode == .hold
        ? OJDLocalized.string("ui.profiles.hold")
        : OJDLocalized.string("ui.profiles.toggle")
      return "\(mode): \(RuntimePresentation.sourceLabel(layer.activator))"
    }
  }

  /// The Controller section of the editor: the details, the output policy, the motion, stick,
  /// trigger and touch settings, and the lighting.
  struct ProfileControllerSection: View {
    /// The profile.
    let profile: RemappingProfile
    /// What the profile's controller has.
    let capabilities: ControllerProfileCapabilities
    /// Opens a sheet.
    let openSheet: (ProfileEditorSheet) -> Void
    /// Sets the output policy.
    let updateOutputPolicy: (RemappingOutputPolicy) -> Void
    /// Sets the physical color.
    let updatePhysicalColor: (ControllerColor?) -> Void

    /// The sections of the Controller tab.
    var body: some View {
      Group {
        Section(header: Text(OJDLocalized.string("ui.profiles.details"))) {
          OJDLabeledValue(
            OJDLocalized.string("term.controller"),
            OJDValue.usbIdentifier(
              vendorID: profile.device.vendorID,
              productID: profile.device.productID
            )
          )
          OJDLabeledValue(
            OJDLocalized.string("ui.profiles.target"),
            RuntimePresentation.profileScopeLabel(profile.applicationScope)
          )
        }
        Section {
          ProfileOutputPolicyView(policy: profile.outputPolicy, onChange: updateOutputPolicy)
        }
        Section {
          configurationRow(
            title: OJDLocalized.string("ui.profiles.motion.title"),
            summary: OJDLocalized.string("ui.profiles.motion.space")
              + " · " + OJDLocalized.string("ui.profiles.gyro.output"),
            supported: capabilities.physicalInput.motion
          ) { openSheet(.motion) }
          configurationRow(
            title: OJDLocalized.string("ui.profiles.stick.title"),
            summary: assignmentCountLabel(profile.stickMappings.count),
            supported: capabilities.supportsStickAxes,
            enabled: capabilities.supportsStickAxes || !profile.stickMappings.isEmpty
          ) { openSheet(.sticks) }
          configurationRow(
            title: OJDLocalized.string("ui.profiles.trigger.title"),
            summary: assignmentCountLabel(profile.triggerMappings.count),
            supported: capabilities.supportsAnalogTriggers,
            enabled: capabilities.supportsAnalogTriggers || !profile.triggerMappings.isEmpty
          ) { openSheet(.triggers) }
          configurationRow(
            title: OJDLocalized.string("ui.profiles.touch.title"),
            summary: assignmentCountLabel(profile.touchMappings.count),
            supported: !capabilities.physicalInput.touchSurfaces.isEmpty,
            enabled: capabilities.physicalInput.touchContactCount > 0
              || !profile.touchMappings.isEmpty
          ) { openSheet(.touch) }
          configurationRow(
            title: OJDLocalized.string("ui.profiles.region.title"),
            summary: OJDLocalized.string("ui.profiles.region.summary"),
            supported: capabilities.supportsStickAxes || capabilities.supportsAnalogTriggers
              || !capabilities.physicalInput.touchSurfaces.isEmpty
          ) { openSheet(.regions) }
          configurationRow(
            title: OJDLocalized.string("ui.profiles.pointerSpeed.title"),
            summary: profile.pointerSpeed.map {
              OJDLocalized.string(
                $0.driver.type == .trigger
                  ? "ui.profiles.pointerSpeed.driverTrigger"
                  : "ui.profiles.pointerSpeed.driverStickDepth"
              )
            } ?? OJDLocalized.string("ui.inputTest.off"),
            supported: true
          ) { openSheet(.pointerSpeed) }
        }
        ProfileLightingEditor(color: profile.physicalColor, onChange: updatePhysicalColor).disabled(
          !capabilities.physicalOutput.lightingFeatures.contains(.programmableColor)
            && profile.physicalColor == nil
        )
      }
    }

    /// A row with `title` and a `summary`, or a note that the controller does not support it, and
    /// an Adjust button.
    ///
    /// - Parameters:
    ///   - title: The name of the setting.
    ///   - summary: The text shown when the controller supports the setting.
    ///   - supported: Whether the controller supports the setting.
    ///   - enabled: Whether the button works; nil follows `supported`.
    ///   - action: Opens the sheet of the setting.
    /// - Returns: The row.
    private func configurationRow(
      title: String,
      summary: String,
      supported: Bool,
      enabled: Bool? = nil,
      action: @escaping () -> Void
    ) -> some View {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
          Text(supported ? summary : OJDLocalized.string("ui.profiles.notSupportedByController"))
            .font(.caption).foregroundColor(
              supported ? Color(NSColor.secondaryLabelColor) : Color(NSColor.systemOrange)
            ).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        OJDCompactSymbolButton(
          symbolName: "pencil",
          label: OJDLocalized.string("action.adjust")
        ) { action() }.disabled(!(enabled ?? supported))
      }
    }

    /// Returns the text for the number of assignments.
    private func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("ui.profiles.assignments", count: count)
    }
  }

  /// A button that removes a row.
  @MainActor
  private func removeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      OJDSystemSymbol(name: "minus.circle", fallback: OJDLocalized.string("action.remove")).frame(
        minWidth: 28,
        minHeight: 28
      )
      .contentShape(Rectangle())
    }.buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
      OJDLocalized.string("action.remove")
    )
  }
#endif
