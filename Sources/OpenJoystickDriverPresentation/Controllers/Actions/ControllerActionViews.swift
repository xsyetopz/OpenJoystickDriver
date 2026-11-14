#if canImport(SwiftUI) && canImport(AppKit)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The virtual gamepad actions of one controller: export its mapping, launch a game with it,
  /// and return every override to automatic.
  struct VirtualGamepadActionsView: View {
    /// The controller.
    let device: ApplicationServiceDeviceDescription
    /// Every connected controller; nil while the service status is not available.
    let connectedDevices: [ApplicationServiceDeviceDescription]?
    /// The model of the app's view of the service, which resets the overrides.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The state and results of the actions.
    @ObservedObject
    var actions: ControllerDetailActions
    /// Whether the reset confirmation shows.
    @State
    private var confirmsResetAll = false
    /// The message of the latest failed reset, or nil.
    @State
    private var resetAllFailure: String?

    /// The Export Mapping and Launch rows when the controller has a virtual gamepad profile, the
    /// Reset row, and the results of the actions.
    var body: some View {
      Group {
        if let profile = VirtualGamepadExport.profile(for: device) {
          OJDLabeledRow(OJDLocalized.string("ui.controllers.exportMapping")) {
            Button(OJDLocalized.string("action.export")) { export(profile) }
              .help(OJDLocalized.string("ui.help.exportMapping"))
          }
          launchRows

          if let outcome = actions.launchOutcome {
            ControllerNoticeText(text: outcome.message, isError: isFailure(outcome))
          }
        }
        OJDLabeledRow(OJDLocalized.string("ui.controllers.virtual.resetAll")) {
          Button(OJDLocalized.string("action.reset")) { confirmsResetAll = true }
            .help(OJDLocalized.string("ui.help.resetAll"))
        }
        if let failure = resetAllFailure { ControllerNoticeText(text: failure, isError: true) }
        if let notice = actions.notice, notice.source == .exportMapping {
          ControllerNoticeText(text: notice.text, isError: notice.isError)
        }
      }.alert(isPresented: $confirmsResetAll) {
        Alert(
          title: Text(OJDLocalized.string("cli.virtual.reset.allSummary")),
          primaryButton: .destructive(Text(OJDLocalized.string("action.reset"))) {
            Task { @MainActor in
              resetAllFailure = await viewModel.resetAllVirtualHIDProfileOverrides()
            }
          },
          secondaryButton: .cancel()
        )
      }
    }

    /// The Launch row and, under it, the SDL hints note for each profile that needs a game
    /// controller backend.
    @ViewBuilder
    private var launchRows: some View {
      OJDLabeledRow(OJDLocalized.string("ui.controllers.launch")) {
        if connectedDevices == nil {
          Text(OJDLocalized.string("status.unavailable"))
        } else {
          Button(OJDLocalized.string("ui.controllers.launch.prompt")) { launch() }
            .help(OJDLocalized.string("ui.help.launch"))
        }
      }
      if let devices = connectedDevices {
        let needed = Result { try VirtualGamepadLaunch.profilesNeedingBackend(in: devices) }
        switch needed {
        case .success(let profiles):
          ForEach(profiles, id: \.self) { profile in
            Text(
              OJDLocalized.formatted(
                "cli.virtual.group.sdlHintsNote",
                CommandLineName.kebab(profile.rawValue)
              )
            ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        case .failure(let error):
          ControllerNoticeText(text: RuntimePresentation.userFacingError(error), isError: true)
        }
      }
    }

    /// Returns whether the launch ended in a failure.
    ///
    /// - Parameter outcome: The outcome of the launch.
    /// - Returns: Whether the launch ended in a failure.
    private func isFailure(_ outcome: VirtualGamepadLaunch.Outcome) -> Bool {
      if case .failed = outcome { return true }
      return false
    }

    /// Asks where to save the mapping and writes it there.
    ///
    /// - Parameter profile: The virtual gamepad profile to export.
    private func export(_ profile: VirtualHIDProfileID) {
      actions.clearNotice()
      ControllerFilePanels.exportMapping(profile: profile) { choice in
        guard let choice else { return }
        actions.exportMapping(format: choice.format, profile: profile, to: choice.url)
      }
    }

    /// Asks for a program and launches it with the mapping of every connected virtual gamepad.
    private func launch() {
      guard let connectedDevices else { return }
      ControllerFilePanels.chooseProgram { choice in
        guard let choice else { return }
        actions.launch(
          program: choice.program,
          devices: connectedDevices,
          gameControllerBackend: choice.gameControllerBackend
        )
      }
    }
  }

  /// A result line under an action; a failure is red with the failure symbol.
  struct ControllerNoticeText: View {
    /// The text of the line.
    let text: String
    /// Whether the line reports a failure.
    let isError: Bool

    /// The line.
    var body: some View {
      Text(text).font(.body).foregroundColor(
        isError
          ? Color(SemanticState.failure.presentation.tone.color)
          : Color(NSColor.secondaryLabelColor)
      ).fixedSize(horizontal: false, vertical: true)
    }
  }

  /// The Capture Packets, Draft Record and Draft Record from SDL buttons, under Advanced.
  struct ControllerTimedActionRows: View {
    /// The controller the buttons act on.
    let device: ApplicationServiceDeviceDescription
    /// The state and results of the actions.
    @ObservedObject
    var actions: ControllerDetailActions

    /// The three buttons.
    @ViewBuilder
    private var actionButtons: some View {
      Button(OJDLocalized.string("ui.controllers.capturePackets")) {
        actions.clearNotice()
        actions.timedKind = .capturePackets
      }.help(OJDLocalized.string("ui.help.capturePackets"))
      Button(OJDLocalized.string("ui.controllers.draftRecord")) {
        actions.clearNotice()
        actions.timedKind = .draftRecord
      }.help(OJDLocalized.string("ui.help.draftRecord"))
      Button(OJDLocalized.string("ui.controllers.draftRecordFromSDL")) {
        actions.clearNotice()
        actions.draftFromSDL(device: device)
      }.help(OJDLocalized.string("ui.help.draftRecordFromSDL"))
    }

    /// The three buttons and the result of the latest of their actions.
    var body: some View {
      Group {
        // One row; a column when the three titles do not fit the width. `ViewThatFits` needs
        // macOS 13, so macOS 12 keeps the row.
        if #available(macOS 13, *) {
          ViewThatFits(in: .horizontal) {
            HStack { actionButtons }
            VStack(alignment: .leading) { actionButtons }
          }
        } else {
          HStack { actionButtons }
        }
        if let notice = actions.notice, notice.source == .timedCapture {
          ControllerNoticeText(text: notice.text, isError: notice.isError)
        }
      }
    }
  }

  /// The sheet of a timed capture: the duration, the instruction, and the progress.
  struct ControllerTimedActionSheet: View {
    /// Whether the sheet captures packets or drafts a controller record.
    let kind: ControllerDetailActions.TimedKind
    /// The controller to capture.
    let device: ApplicationServiceDeviceDescription
    /// The gateway that streams the packets.
    let gateway: any ControllerDiagnosticsGateway
    /// The state and results of the actions.
    @ObservedObject
    var actions: ControllerDetailActions
    /// The capture duration as typed.
    @State
    private var durationText = CaptureDuration.text(for: CaptureDuration.defaultSeconds)

    /// The duration in seconds, or nil when the text is not a valid duration.
    private var seconds: Double? { CaptureDuration.parse(durationText) }

    /// The vendor and product ID of the controller.
    private var identity: String {
      unsafe String(format: "%04X:%04X", device.vendorID, device.productID)
    }

    /// Whether a capture runs.
    private var isCapturing: Bool { actions.timedState == .capturing }

    /// The title, the instruction, the duration field, the failures, and the Cancel and Start
    /// Capture buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Text(
          OJDLocalized.string(
            kind == .draftRecord
              ? "ui.controllers.draftRecord.title" : "ui.controllers.capturePackets.title"
          )
        ).font(.headline)
        Text(instruction).fixedSize(horizontal: false, vertical: true)
        if kind == .capturePackets {
          Text(OJDLocalized.string("ui.developer.packetSharingWarning")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        HStack {
          Text(OJDLocalized.string("ui.controllers.captureDuration"))
          TextField("", text: $durationText).frame(width: 80).multilineTextAlignment(.trailing)
            .disabled(isCapturing)
            .ojdAccessibilityLabel(OJDLocalized.string("ui.controllers.captureDuration"))
        }
        if seconds == nil {
          ControllerNoticeText(
            text: OJDLocalized.string("ui.controllers.captureDurationInvalid"),
            isError: true
          )
        }
        if case .failed(let message) = actions.timedState {
          ControllerNoticeText(text: message, isError: true)
        }
        HStack {
          if isCapturing {
            ProgressView().controlSize(.small)
            Text(OJDLocalized.string("ui.developer.capturing"))
          }
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { actions.cancelTimed() }
            .keyboardShortcut(.cancelAction).help(OJDLocalized.string("ui.help.cancelSheet"))
          Button(OJDLocalized.string("ui.developer.startCapture")) { start() }
            .keyboardShortcut(.defaultAction).disabled(seconds == nil || isCapturing)
            .help(OJDLocalized.string("ui.help.startCapture"))
        }
      }.ojdSheet(.compact)
    }

    /// The instruction for the kind of capture, with the controller's name and ID.
    private var instruction: String {
      OJDLocalized.formatted(
        kind == .draftRecord ? "cli.record.draft.started" : "cli.controller.capture.started",
        device.name,
        identity
      )
    }

    /// Starts the capture for the typed duration; the controller's report descriptor is read when
    /// the capture ends.
    private func start() {
      guard let seconds else { return }
      let controller = device
      actions.startTimed(
        kind,
        device: controller,
        gateway: gateway,
        seconds: seconds
      ) { ControllerRecordDrafting.physicalDescriptor(for: controller) }
    }
  }

#endif
