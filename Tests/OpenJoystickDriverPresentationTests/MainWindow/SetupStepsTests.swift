import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct SetupStepsTests {
  private func status(
    inputRead: PermissionManager.AccessState = .granted,
    inputInject: PermissionManager.AccessState = .granted,
    bluetooth: BluetoothAccessState? = .granted
  ) -> (RuntimePermissionLoadState, RuntimeStatusState) {
    let payload = ApplicationServiceStatusPayload(
      inputRead: inputRead,
      inputInject: inputInject,
      connectedDevices: [],
      bluetoothAccess: bluetooth
    )
    let presentation = RuntimeStatusPresentation(payload: payload)
    return (.available(presentation.permissions), .available(presentation))
  }

  @Test
  func nothingOpenWhenEveryAccessGranted() {
    let (permissions, state) = status()
    #expect(SetupSteps.open(permissionState: permissions, statusState: state).isEmpty)
  }

  @Test
  func eachMissingAccessOneStepInOrder() {
    let (permissions, state) = status(
      inputRead: .denied,
      inputInject: .denied,
      bluetooth: .notAsked
    )
    let steps = SetupSteps.open(permissionState: permissions, statusState: state)
    #expect(steps.map(\.kind) == [.permission(.inputRead), .permission(.inputInject), .bluetooth])
  }

  @Test
  func accessibilityOneStepWhenInputInjectAndPostEventBothOpen() {
    let payload = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .denied,
      connectedDevices: []
    )
    let presentation = RuntimeStatusPresentation(
      payload: payload,
      postEventAccess: .notAuthorized,
      requiresPostEventAccess: true
    )
    let steps = SetupSteps.open(
      permissionState: .available(presentation.permissions),
      statusState: .available(presentation)
    )
    #expect(steps.map(\.kind) == [.permission(.inputInject)])
  }

  @Test
  func undecidedBluetoothStepAsksAndDeniedOneOpensSystemSettings() {
    let (undecidedPermissions, undecided) = status(bluetooth: .notAsked)
    let asks = SetupSteps.open(permissionState: undecidedPermissions, statusState: undecided)
    #expect(asks.first?.buttonKey == "action.request")
    let (deniedPermissions, denied) = status(bluetooth: .denied)
    let opens = SetupSteps.open(permissionState: deniedPermissions, statusState: denied)
    #expect(opens.first?.buttonKey == "platform.macos.ui.setup.openSystemSettings")
  }

  @Test(arguments: [BluetoothAccessState.restricted, .unavailable])
  func bluetoothAccessUserCannotChangeNoStep(state: BluetoothAccessState) {
    let (permissions, status) = status(bluetooth: state)
    #expect(SetupSteps.open(permissionState: permissions, statusState: status).isEmpty)
  }

  @Test
  func everyStepHasItsOwnSentenceAndButtonInEnglish() {
    let (permissions, state) = status(
      inputRead: .denied,
      inputInject: .denied,
      bluetooth: .notAsked
    )
    let steps = SetupSteps.open(permissionState: permissions, statusState: state)
    #expect(Set(steps.map(\.sentenceKey)).count == steps.count)
    for step in steps {
      #expect(OJDLocalized.string(step.sentenceKey) != step.sentenceKey)
      #expect(OJDLocalized.string(step.buttonKey) != step.buttonKey)
    }
  }

  @Test
  func failedRequestShowsItsMessageAndARequestInFlightIsBusy() {
    func failure(
      _ permissions: RuntimePermissionLoadState = .unavailable,
      _ postEvent: RuntimePostEventAccessLoadState = .loading,
      settingsOpenFailed: Bool = false
    ) -> String? {
      SetupSteps.failure(
        permissionState: permissions,
        postEventAccessState: postEvent,
        settingsOpenFailed: settingsOpenFailed
      )
    }
    #expect(failure() == nil)
    #expect(failure(.error("no service")) == "no service")
    #expect(failure(.unavailable, .error("no post event")) == "no post event")
    #expect(failure(.unavailable, .unavailable("offline")) == "offline")
    #expect(
      failure(settingsOpenFailed: true)
        == OJDLocalized.string("platform.macos.ui.setup.openSystemSettingsFailed")
    )
    #expect(SetupSteps.isRequesting(permissionState: .requesting, postEventAccessState: .loading))
    #expect(
      SetupSteps.isRequesting(
        permissionState: .loading,
        postEventAccessState: .requesting
      )
    )
    #expect(!SetupSteps.isRequesting(permissionState: .unavailable, postEventAccessState: .loading))
  }

  @Test
  func stepsShowOnlyWhenFirstLoadFoundOneOpen() {
    var gate = SetupStepsGate()
    gate.update(loaded: false, openSteps: 0)
    #expect(!gate.isShown)
    gate.update(loaded: true, openSteps: 2)
    #expect(gate.isShown)
    gate.update(loaded: true, openSteps: 0)
    #expect(!gate.isShown)

    var clean = SetupStepsGate()
    clean.update(loaded: true, openSteps: 0)
    clean.update(loaded: true, openSteps: 1)
    #expect(!clean.isShown)
  }

  @Test
  func dismissingHidesStepsForGood() {
    var gate = SetupStepsGate()
    gate.update(loaded: true, openSteps: 1)
    gate.dismiss()
    gate.update(loaded: true, openSteps: 1)
    #expect(!gate.isShown)
  }

  @Test
  @MainActor
  func bluetoothRequestGoesThroughServiceAndUpdatesStatus() async {
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [],
        bluetoothAccess: .notAsked
      )
    )
    let model = RuntimeViewModel(gateway: gateway)
    await model.refresh()
    let answer = await model.requestBluetoothAccess()
    #expect(answer == .granted)
    #expect(await gateway.bluetoothRequests == 1)
    guard case .available(let presentation) = model.statusState else {
      Issue.record("status is not available")
      return
    }
    #expect(presentation.bluetoothAccess == .granted)
  }

  @Test
  @MainActor
  func failedBluetoothRequestShowsWhyUntilTheNextRequest() async {
    let gateway = GatewayStub()
    await gateway.setBluetoothShouldFail(true)
    let model = RuntimeViewModel(gateway: gateway)

    #expect(await model.requestBluetoothAccess() == nil)
    #expect(
      model.bluetoothRequestFailure
        == RuntimePresentation.userFacingError(ApplicationServiceClientError.timeout)
    )

    await gateway.setBluetoothShouldFail(false)
    #expect(await model.requestBluetoothAccess() == .granted)
    #expect(model.bluetoothRequestFailure == nil)
  }
}
