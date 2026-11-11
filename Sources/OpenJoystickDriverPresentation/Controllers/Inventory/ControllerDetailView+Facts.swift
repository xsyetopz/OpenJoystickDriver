#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ControllerDetailView {

    /// The detail form: the header, the suspended session, the facts, Input Test, the server
    /// picker, the virtual gamepad rows, the Tuning section and Advanced.
    var body: some View {
      Form {
        Section { controllerHeader }
        if showsSessionState {
          Section {
            if device.sessionState == .suspended {
              OJDLabeledRow(OJDLocalized.string("ui.controllers.suspended")) {
                Button(OJDLocalized.string("ui.menu.controller.resume")) {
                  Task { @MainActor in await viewModel.resumeController(device) }
                }
              }
            }
            if let failure = viewModel.controllerActionFailures[device.sessionToken.rawValue] {
              controllerActionFailure(failure)
            }
          }
        }
        Section {
          activeProfileRow
          ForEach(
            ControllerDetailFacts.general(for: device, appName: ProfileAppChoices.appName)
          ) { fact in
            if fact.kind == .serialNumber {
              SerialNumberRow(label: fact.label, serial: fact.value, visibility: $serialVisibility)
            } else {
              OJDLabeledValue(fact.label, fact.value)
            }
          }
        }
        Section { inputTestAction }
        if device.isHeldByAppleDriver {
          Section {
            OJDLabeledValue(
              OJDLocalized.string("platform.macos.ui.controllers.servedByMacOS"),
              OJDLocalized.string("platform.macos.ui.controllers.servedByMacOSDetail")
            )
            ControllerClaimButton(viewModel: viewModel)
          }
        }
        if ControllerServerPicker.isShown(for: device) {
          Section {
            ControllerServerPicker(
              viewModel: viewModel,
              device: device,
              hasRecord: record != nil || !hasLoadedRecord
            )
            if let record {
              OJDLabeledValue(
                OJDLocalized.string("ui.controllers.server.source"),
                ControllerDetailFacts.serverSourceText(record)
              )
            }
          }
        }
        if device.physicalOwnership != .systemGamepad {
          // A per-controller identity resets the picker state on a different selection.
          Section {
            VirtualHIDProfileOverrideView(viewModel: viewModel, device: device).id(
              device.sessionToken.rawValue
            )
          }
          Section {
            VirtualGamepadActionsView(
              device: device,
              connectedDevices: connectedDevices,
              viewModel: viewModel,
              actions: actions
            )
          }
        }
        if let record {
          Section {
            StickDeadzoneRow(
              viewModel: viewModel,
              device: device,
              setting: StickDeadzoneSetting(record: record)
            ) { await loadRecord() }
            tuningDisclosure(for: record)
          }
        }
        Section { advancedDisclosure }
      }.task(id: recordLoadID) { await loadRecord() }.sheet(item: $actions.timedKind) { kind in
        ControllerTimedActionSheet(
          kind: kind,
          device: device,
          gateway: viewModel.gateway,
          actions: actions
        )
      }.onReceive(actions.$pendingSave) { request in
        guard let request else { return }
        ControllerFilePanels.save(request) { actions.finishSave(to: $0) }
      }.ojdGroupedForm().accessibilityElement(children: .contain)
        .ojdAccessibilityLabel(device.name).ojdAccessibilityValue(accessibilityValue)
    }

    /// Reloads the record when the controller or who serves its model changes.
    private var recordLoadID: String {
      "\(device.sessionToken.rawValue) \(device.recordServer.rawValue)"
    }

    /// Reads the effective record of the controller's model off the main actor.
    private func loadRecord() async {
      let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
      record = await Task.detached { ControllerRecordSet.load().records[model] }.value
      hasLoadedRecord = true
    }

    /// Every connected controller; nil while the service status is not available.
    private var connectedDevices: [ApplicationServiceDeviceDescription]? {
      if case .available(let status) = viewModel.statusState { return status.devices }
      return nil
    }

    /// The remapping profile active for the controller's model, if there is one.
    private var activeRemappingProfile: RemappingProfile? {
      guard case .available(let snapshot) = viewModel.remappingState,
        let active = snapshot.activeProfiles.routingActiveProfile(
          vendorID: device.vendorID,
          productID: device.productID
        )
      else { return nil }
      return snapshot.profiles.first { $0.id == active.profileID }
    }

    /// The effective tuning values, collapsed by default.
    ///
    /// The whole label row toggles.
    ///
    /// - Parameter record: The effective record of the controller's model.
    /// - Returns: The disclosure group.
    private func tuningDisclosure(for record: ControllerRecord) -> some View {
      DisclosureGroup(isExpanded: $showsTuning) {
        ForEach(ControllerTuningRows.rows(for: record, activeProfile: activeRemappingProfile)) {
          OJDLabeledValue($0.name, $0.text)
        }
      } label: {
        Button(OJDLocalized.string("cli.controller.show.labelTuning")) { showsTuning.toggle() }
          .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    /// Suspending, resuming and disconnecting a wireless link are commands of the Controller menu
    /// and the status item; the detail shows only a suspended session and a failed command.
    private var showsSessionState: Bool {
      device.sessionState == .suspended
        || viewModel.controllerActionFailures[device.sessionToken.rawValue] != nil
    }

    /// The identifiers and endpoints.
    ///
    /// The whole label row toggles, not only the chevron.
    private var advancedDisclosure: some View {
      DisclosureGroup(isExpanded: $showsAdvanced) {
        ForEach(ControllerDetailFacts.advanced(for: device, record: record)) { fact in
          OJDLabeledValue(fact.label, fact.value)
        }
        ControllerTimedActionRows(device: device, actions: actions)
      } label: {
        Button(OJDLocalized.string("ui.virtualProfile.advanced")) { showsAdvanced.toggle() }
          .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    /// Returns the failed command with the failure symbol and its message.
    ///
    /// - Parameter message: The message of the failure.
    /// - Returns: The failed command with the failure symbol and its message.
    private func controllerActionFailure(_ message: String) -> some View {
      HStack(alignment: .top, spacing: OJDSpacing.small) {
        OJDSystemSymbol(
          name: SemanticState.failure.presentation.symbolName,
          fallback: OJDLocalized.string("status.needsAttention")
        ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
        Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }.ojdAccessibilityLabel(
        OJDLocalized.string("status.needsAttention")
      ).ojdAccessibilityValue(message)
    }

    /// The Input Test row with its Open button, disabled while the session is suspended.
    private var inputTestAction: some View {
      OJDLabeledRow(OJDLocalized.string("ui.inputTest.title")) {
        Button(OJDLocalized.string("ui.inputTest.open")) {
          openInputTest(device)
        }.disabled(device.sessionState == .suspended)
      }
    }

    /// The header: the controller's glyph, its name and its connection.
    private var controllerHeader: some View {
      HStack(alignment: .center, spacing: OJDSpacing.medium) {
        let presentation = device.publishedIdentityPresentation
        OJDSystemSymbol(
          name: presentation.controllerSymbolName,
          fallback: nil,
          fallbackSymbolName: presentation.controllerSymbolFallback
        ).font(.title).foregroundColor(presentation.glyphFamily.controllerSymbolColor)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
          Text(device.name).font(.headline.weight(.semibold)).lineLimit(1)
          Text(connectionValue.displayText)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 0)
      }
    }

    /// The Active Profile row: checking, none, the profile's name, or the failure.
    @ViewBuilder
    private var activeProfileRow: some View {
      switch activeProfile {
      case .loading:
        OJDLabeledValue(
          OJDLocalized.string("ui.controllers.activeProfile"),
          OJDLocalized.string("status.checking")
        )
      case .noProfile:
        OJDLabeledValue(
          OJDLocalized.string("ui.controllers.activeProfile"),
          OJDLocalized.string("status.none")
        )
      case .profile(let name):
        OJDLabeledValue(
          OJDLocalized.string("ui.controllers.activeProfile"),
          device.profileInForce?.name ?? name
        )
      case .unavailable(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "ui.controllers.profileUnavailable"
          ),
          message: message
        )
      case .error(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "ui.controllers.profileLoadError"
          ),
          message: message
        )
      }
    }

    /// Returns the Active Profile row for a profile that cannot be read, with Try Again.
    ///
    /// - Parameters:
    ///   - label: The kind of the failure.
    ///   - message: The message of the failure.
    /// - Returns: The Active Profile row for a profile that cannot be read, with Try Again.
    private func profileFailureRow(label: String, message: String) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        HStack {
          Text(OJDLocalized.string("ui.controllers.activeProfile"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
          Spacer()
          Text(OJDLocalized.string("status.needsAttention"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }

        Text(label).font(.caption.weight(.semibold))
        Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        Button(OJDLocalized.string("action.tryAgain"), action: retry)

      }
    }

    /// The controller's connection as reported.
    var connectionValue: OJDValue { .reported(device.connection) }
  }

#endif
