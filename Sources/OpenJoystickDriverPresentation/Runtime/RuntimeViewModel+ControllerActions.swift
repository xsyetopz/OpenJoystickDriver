import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// The button labels of the connected controller `selector` names; standard when unknown.
  func buttonLabels(for selector: RuntimeDeviceSelector) -> ControllerButtonLabels {
    guard case .available(let status) = statusState,
      let device = status.devices.first(where: { device in
        device.vendorID == selector.vendorID && device.productID == selector.productID
          && (selector.runtimeIdentifier == nil
            || selector.runtimeIdentifier == device.runtimeIdentifier)
      })
    else { return .standard }
    return ControllerButtonLabels(protocolID: device.protocolBinding.protocolID)
  }

  func listenForInput(for selector: RuntimeDeviceSelector) async {
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
              to: state,
              labels: buttonLabels(for: selector)
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
        "error.noDetectedControl"
      )
    )
  }

  func cancelInputCapture() {
    inputGeneration += 1
    inputCaptureState = .idle
  }

  func pairRemappingJoyCons(left: String, right: String, profileID: UUID) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "error.actionInProgress"
      )
    }
    do {
      remappingState = .available(
        try await gateway.pairRemappingJoyCons(left: left, right: right, profileID: profileID)
      )
      return nil
    } catch { return RuntimePresentation.userFacingError(error) }
  }

  func unpairRemappingJoyCons(sessionID: UUID) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "error.actionInProgress"
      )
    }
    do {
      remappingState = .available(try await gateway.unpairRemappingJoyCons(sessionID: sessionID))
      return nil
    } catch { return RuntimePresentation.userFacingError(error) }
  }

  /// Stores `profile` as the virtual HID profile override of `device`'s model, or clears the
  /// override when `profile` is nil so the controller selects automatically.
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID?,
    for device: ApplicationServiceDeviceDescription
  ) async {
    // The service retargets every controller of the model, so the request and its failure
    // belong to the model rather than to one controller.
    let model = RuntimeControllerModel(device)
    guard virtualHIDProfileOverrideStates[model]?.inFlight != true else { return }
    virtualHIDProfileOverrideStates[model] = RuntimeVirtualHIDProfileOverrideState(
      request: profile.map { .set($0) } ?? .reset
    )
    let selector = RuntimeDeviceSelector(device: device)
    var failure: String?
    do {
      let result: VirtualHIDProfileOverrideResult
      if let profile {
        result = try await gateway.setVirtualHIDProfileOverride(profile, for: selector)
      } else {
        result = try await gateway.resetVirtualHIDProfileOverride(for: selector)
      }
      failure = result.failure.map(RuntimePresentation.virtualHIDProfileOverrideFailure)
    } catch { failure = RuntimePresentation.userFacingError(error) }
    // Keep the request in flight until the refreshed status carries the model's new profile.
    await refreshControllerInventory()
    virtualHIDProfileOverrideStates[model] = failure.map {
      RuntimeVirtualHIDProfileOverrideState(failure: $0)
    }
  }

  func suspendController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.suspendController(RuntimeDeviceSelector(device: device))
      guard result.succeeded || result.failure == .alreadySuspended else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      return nil
    }
  }

  func resumeController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.resumeController(RuntimeDeviceSelector(device: device))
      guard result.succeeded || result.failure == .alreadyActive else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      return nil
    }
  }

  func disconnectWirelessController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.disconnectWirelessController(
        RuntimeDeviceSelector(device: device)
      )
      guard !result.succeeded else { return nil }
      let stage = result.failedStage?.rawValue ?? "disconnect-wireless-controller"
      let cause = result.detail ?? result.failure?.rawValue ?? "unknown failure"
      let code = result.systemCode.map { " (\($0))" } ?? ""
      // The stage, cause, and code are service identifiers; the view labels them localized.
      let message = "\(stage): \(cause)\(code)"
      return result.recovery.map { "\(message). \($0)" } ?? message
    }
  }

  /// Runs `action` for `device`, refreshes the inventory, then records the failure `action`
  /// returned or threw so the controller's detail view shows it.
  private func performControllerAction(
    _ device: ApplicationServiceDeviceDescription,
    _ action: () async throws -> String?
  ) async {
    controllerActionFailures[device.runtimeIdentifier] = nil
    var failure: String?
    do { failure = try await action() } catch {
      failure = RuntimePresentation.userFacingError(error)
    }
    await refreshControllerInventory()
    controllerActionFailures[device.runtimeIdentifier] = failure
  }
}
