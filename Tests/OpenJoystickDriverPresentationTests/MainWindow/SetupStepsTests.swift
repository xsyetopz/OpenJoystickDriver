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
  func nothingIsOpenWhenEveryAccessIsGranted() {
    let (permissions, state) = status()
    #expect(SetupSteps.open(permissionState: permissions, statusState: state).isEmpty)
  }

  @Test
  func eachMissingAccessIsOneStepInOrder() {
    let (permissions, state) = status(
      inputRead: .denied,
      inputInject: .denied,
      bluetooth: .notAsked
    )
    let steps = SetupSteps.open(permissionState: permissions, statusState: state)
    #expect(steps.map(\.kind) == [.permission(.inputRead), .permission(.inputInject), .bluetooth])
  }

  @Test
  func anUndecidedBluetoothStepAsksAndADeniedOneOpensSystemSettings() {
    let (undecidedPermissions, undecided) = status(bluetooth: .notAsked)
    let asks = SetupSteps.open(permissionState: undecidedPermissions, statusState: undecided)
    #expect(asks.first?.buttonKey == "action.request")
    let (deniedPermissions, denied) = status(bluetooth: .denied)
    let opens = SetupSteps.open(permissionState: deniedPermissions, statusState: denied)
    #expect(opens.first?.buttonKey == "platform.macos.ui.setup.openSystemSettings")
  }

  @Test(arguments: [BluetoothAccessState.restricted, .unavailable])
  func aBluetoothAccessTheUserCannotChangeIsNoStep(state: BluetoothAccessState) {
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
  func theStepsShowOnlyWhenTheFirstLoadFoundOneOpen() {
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
  func dismissingHidesTheStepsForGood() {
    var gate = SetupStepsGate()
    gate.update(loaded: true, openSteps: 1)
    gate.dismiss()
    gate.update(loaded: true, openSteps: 1)
    #expect(!gate.isShown)
  }

  @Test
  @MainActor
  func theBluetoothRequestGoesThroughTheServiceAndUpdatesTheStatus() async {
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
}
