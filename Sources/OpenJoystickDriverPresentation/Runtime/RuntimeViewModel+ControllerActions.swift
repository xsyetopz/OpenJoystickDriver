import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// Waits for the user to press a control of the controller and publishes the detected source in
  /// ``inputCaptureState``.
  ///
  /// It compares each input state with the one before it, reads every 100 ms at most 50 times, and
  /// reports that no control was detected when none arrives.
  func listenForInput(for selector: ControllerReference) async {
    inputGeneration += 1
    let generation = inputGeneration
    inputCaptureState = .listening(selector)
    var baselineState: ControllerState?

    for attempt in 0..<50 {
      guard generation == inputGeneration else { return }
      do {
        if let state = try await gateway.controllerState(for: selector) {
          guard generation == inputGeneration else { return }
          if let baselineState,
            let detectedSource = RuntimePresentation.detectedTransition(
              from: baselineState,
              to: state
            )
          {
            inputCaptureState = .detected(selector, state, detectedSource)
            return
          }
          baselineState = state
        }
        if attempt < 49 { try await Task.sleep(nanoseconds: 100_000_000) }
      } catch is CancellationError {
        guard generation == inputGeneration else { return }
        inputCaptureState = .idle
        return
      } catch {
        guard generation == inputGeneration else { return }
        let message = RuntimePresentation.userFacingError(error)
        inputCaptureState =
          RuntimePresentation.isUnavailable(error)
          ? .unavailable(selector, message) : .error(selector, message)
        return
      }
    }

    guard generation == inputGeneration else { return }
    inputCaptureState = .unavailable(
      selector,
      OJDLocalized.string(
        "ui.error.noDetectedControl"
      )
    )
  }

  /// Ends the input capture.
  func cancelInputCapture() {
    inputGeneration += 1
    inputCaptureState = .idle
  }

  /// Pairs two Joy-Con controllers under a profile.
  ///
  /// Returns the message of a failure, or nil; a running change refuses the request.
  func pairRemappingJoyCons(
    left: ControllerReference,
    right: ControllerReference,
    profileID: UUID
  ) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "ui.error.actionInProgress"
      )
    }
    do {
      remappingState = .available(
        try await gateway.pairRemappingJoyCons(left: left, right: right, profileID: profileID)
      )
      return nil
    } catch { return RuntimePresentation.userFacingError(error) }
  }

  /// Unpairs a Joy-Con session.
  ///
  /// Returns the message of a failure, or nil; a running change refuses the request.
  func unpairRemappingJoyCons(sessionID: UUID) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "ui.error.actionInProgress"
      )
    }
    do {
      remappingState = .available(try await gateway.unpairRemappingJoyCons(sessionID: sessionID))
      return nil
    } catch { return RuntimePresentation.userFacingError(error) }
  }

  /// Handles the choice of `profile` in `scope` in the Virtual HID profile pop-up: it sends the
  /// change when it would change something, and otherwise keeps in
  /// ``virtualHIDProfileOverrideStates`` the notice that says why nothing was sent.
  ///
  /// - Parameters:
  ///   - profile: The kind chosen, or nil for Automatic.
  ///   - scope: The scope the person chose.
  ///   - device: The controller.
  func chooseVirtualHIDProfile(
    _ profile: VirtualHIDProfileID?,
    scope: VirtualHIDProfileScopeChoice,
    for device: ApplicationServiceDeviceDescription
  ) async {
    let model = RuntimeControllerModel(device)
    guard virtualHIDProfileOverrideStates[model]?.inFlight != true else { return }
    switch VirtualHIDProfileOverrideDecision.decide(profile: profile, scope: scope, for: device) {
    case .send:
      await setVirtualHIDProfileOverride(profile, for: device, scope: scope.scope)
    case .unchanged:
      virtualHIDProfileOverrideStates[model] = RuntimeVirtualHIDProfileOverrideState(
        notice: OJDLocalized.string("ui.virtualProfile.unchanged")
      )
    case .otherScopeHolds(let holder):
      virtualHIDProfileOverrideStates[model] = RuntimeVirtualHIDProfileOverrideState(
        notice: OJDLocalized.string(
          holder == .unit
            ? "ui.virtualProfile.otherScopeHolds.unit" : "ui.virtualProfile.otherScopeHolds.model"
        )
      )
    }
  }

  /// Stores `profile` as the virtual HID profile override of the model of `device`, or of `device`
  /// alone for the unit scope.
  ///
  /// A nil `profile` clears the override, so the controller selects automatically. The request
  /// stays in ``virtualHIDProfileOverrideStates`` until the refreshed status shows the result, and
  /// a failure stays there.
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID?,
    for device: ApplicationServiceDeviceDescription,
    scope: VirtualHIDProfileOverrideScope = .model
  ) async {
    // The service retargets every controller of the model, so the request and its failure
    // belong to the model rather than to one controller.
    let model = RuntimeControllerModel(device)
    guard virtualHIDProfileOverrideStates[model]?.inFlight != true else { return }
    virtualHIDProfileOverrideStates[model] = RuntimeVirtualHIDProfileOverrideState(
      request: profile.map { .set($0) } ?? .reset
    )
    let selector = ControllerReference.session(device.sessionToken)
    var failure: String?
    do {
      let result: VirtualHIDProfileOverrideResult
      if let profile {
        result = try await gateway.setVirtualHIDProfileOverride(
          profile,
          for: selector,
          scope: scope
        )
      } else {
        result = try await gateway.resetVirtualHIDProfileOverride(for: selector, scope: scope)
      }
      failure = result.failure.map(RuntimePresentation.virtualHIDProfileOverrideFailure)
    } catch { failure = RuntimePresentation.userFacingError(error) }
    // Keep the request in flight until the refreshed status carries the model's profile.
    await refreshControllerInventory()
    virtualHIDProfileOverrideStates[model] = failure.map {
      RuntimeVirtualHIDProfileOverrideState(failure: $0)
    }
  }

  /// Returns every controller model, also those not connected, to automatic virtual HID profile
  /// selection and refreshes the inventory.
  ///
  /// Returns why the service could not apply it, or nil.
  func resetAllVirtualHIDProfileOverrides() async -> String? {
    var failure: String?
    do {
      if try await !gateway.resetAllVirtualHIDProfileOverrides() {
        failure = OJDLocalized.string("ui.controllers.virtual.resetAllFailed")
      }
    } catch { failure = RuntimePresentation.userFacingError(error) }
    await refreshControllerInventory()
    return failure
  }

  /// Sets who serves the model of `device` to `server`: macOS natively, or OpenJoystickDriver as a
  /// virtual controller.
  ///
  /// A refusal is kept in ``controllerServerFailures`` for the picker to show below itself, with
  /// the service's detail text for a record that is invalid or cannot be written. A choice made
  /// while the model's previous one runs is ignored.
  func setControllerServer(
    _ server: ControllerServer,
    for device: ApplicationServiceDeviceDescription
  ) async {
    let model = RuntimeControllerModel(device)
    guard pendingControllerServers[model] == nil else { return }
    pendingControllerServers[model] = server
    controllerServerFailures[model] = nil
    defer { pendingControllerServers[model] = nil }
    var accepted = false
    controllerServerFailures[model] = await runControllerAction {
      let result = try await gateway.setControllerServer(
        model: ControllerModelID(vendorID: device.vendorID, productID: device.productID),
        server: server
      )
      guard let failure = result.failure else {
        accepted = true
        return nil
      }
      return RuntimePresentation.controllerServerFailure(failure, detail: result.detail)
    }
    guard accepted else { return }
    await waitForRecordServer(server, of: model)
  }

  /// Sets the stick dead zone of the model of `device` in the user's controller record, or removes
  /// it when `value` is nil.
  ///
  /// A refusal shows in the controller's detail, with the service's detail text for a record that
  /// is invalid or cannot be written. Returns whether the service wrote it.
  @discardableResult
  func setStickDeadzone(
    _ value: Double?,
    for device: ApplicationServiceDeviceDescription
  ) async -> Bool {
    var accepted = false
    await performControllerAction(device) {
      let result = try await gateway.setControllerTuning(
        model: ControllerModelID(vendorID: device.vendorID, productID: device.productID),
        key: .stickDeadzone,
        value: value
      )
      guard let failure = result.failure else {
        accepted = true
        return nil
      }
      return RuntimePresentation.controllerTuningFailure(failure, detail: result.detail)
    }
    return accepted
  }

  /// Whether the service is applying a server choice for the model of `device`.
  func isControllerServerRequestRunning(for device: ApplicationServiceDeviceDescription) -> Bool {
    pendingControllerServers[RuntimeControllerModel(device)] != nil
  }

  /// Why the picker cannot offer a server choice for `device`, or nil when it can.
  ///
  /// The service refuses every choice for a model that no controller record describes
  /// (`noRecord`); its other refusals never reach a controller that shows the picker.
  ///
  /// - Parameter hasRecord: Whether a record describes the controller's model.
  func controllerServerUnavailableReason(hasRecord: Bool) -> String? {
    hasRecord ? nil : OJDLocalized.string("ui.controllers.server.noRecord")
  }

  /// The server the picker shows for `device`: the pending choice, or the record's server.
  func shownControllerServer(for device: ApplicationServiceDeviceDescription) -> ControllerServer {
    pendingControllerServers[RuntimeControllerModel(device)] ?? device.recordServer
  }

  /// Refreshes the inventory every 200 ms, at most 10 times, until a controller of `model` reports
  /// `server`.
  ///
  /// The service reloads the records after it answers, so the first refresh can still carry the
  /// previous server.
  private func waitForRecordServer(
    _ server: ControllerServer,
    of model: RuntimeControllerModel
  ) async {
    for _ in 0..<10 {
      if case .available(let status) = statusState,
        status.devices.contains(where: {
          RuntimeControllerModel($0) == model && $0.recordServer == server
        })
      {
        return
      }
      do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
      await refreshControllerInventory()
    }
  }

  /// Suspends the controller; a controller that is suspended already counts as success.
  ///
  /// A failure shows in the controller's detail.
  func suspendController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.suspendController(
        ControllerReference.session(device.sessionToken)
      )
      guard result.succeeded || result.failure == .alreadySuspended else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      return nil
    }
  }

  /// Resumes the controller; a controller that is active already counts as success.
  ///
  /// A failure shows in the controller's detail.
  func resumeController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.resumeController(
        ControllerReference.session(device.sessionToken)
      )
      guard result.succeeded || result.failure == .alreadyActive else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      return nil
    }
  }

  /// Disconnects the wireless link of the controller.
  ///
  /// A failure shows in the controller's detail, and its stage and code are printed.
  func disconnectWirelessController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.disconnectWirelessController(
        ControllerReference.session(device.sessionToken)
      )
      guard let failure = result.failure else { return nil }
      let code = result.systemCode.map(String.init) ?? "none"
      print(
        "[RuntimeViewModel] Wireless disconnect failed: \(failure.rawValue), "
          + "stage \(result.failedStage?.rawValue ?? "none"), code \(code), "
          + "detail \(result.detail ?? "none"), recovery \(result.recovery ?? "none")"
      )
      return ControllerDetailLabels.wirelessDisconnectFailureText(failure)
    }
  }

  /// Runs `action` for `device`, refreshes the inventory, then records the failure `action`
  /// returned or threw so the controller's detail view shows it.
  private func performControllerAction(
    _ device: ApplicationServiceDeviceDescription,
    _ action: () async throws -> String?
  ) async {
    controllerActionFailures[device.sessionToken.rawValue] = nil
    controllerActionFailures[device.sessionToken.rawValue] = await runControllerAction(action)
  }

  /// Runs `action`, refreshes the inventory, and returns the failure `action` returned or threw.
  private func runControllerAction(_ action: () async throws -> String?) async -> String? {
    var failure: String?
    do { failure = try await action() } catch {
      failure = RuntimePresentation.userFacingError(error)
    }
    await refreshControllerInventory()
    return failure
  }
}
