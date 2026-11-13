import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverPresentation

struct ControllerReadinessTests {

  @Test(arguments: [
    (ServingRoute.extensionOwned, false, false, ControllerReadiness.working),
    (.outputDisabled(.userDisabled), false, false, .working),
    (.outputDisabled(.upstreamVirtualDevice), false, false, .working),
    (.extensionOwned, true, false, .needsStep(.grantAccess)),
    (.extensionOwned, false, true, .needsStep(.setUpDriver)),
    (.extensionOwned, true, true, .needsStep(.setUpDriver)),
    (.outputDisabled(.noVirtualProfile), false, false, .notSupported),
    (.outputDisabled(.noVirtualProfile), true, true, .notSupported),
  ])
  func servedControllerStates(
    route: ServingRoute,
    permissionMissing: Bool,
    needsDriver: Bool,
    expected: ControllerReadiness
  ) {
    let input = ControllerReadinessInput(
      subject: .served(route),
      isPermissionMissing: permissionMissing,
      needsDriverStep: needsDriver
    )
    #expect(ControllerReadiness.resolve(input) == expected)
  }

  @Test(arguments: ProtocolBindingReason.allCases)
  func everyUnservedReasonMapsToNonWorkingState(reason: ProtocolBindingReason) {
    let state = ControllerReadiness.resolve(.init(subject: .unserved(reason)))
    #expect(state != .working)
    switch reason {
    case .noProtocolMatch, .ambiguousProtocolMatch, .interfaceContractMismatch,
      .descriptorContractMismatch, .unsupportedProtocolVariant, .unsupportedTransportVariant,
      .virtualProfileUnavailable, .noModeMatched:
      #expect(state == .notSupported)
    case .deviceInUse, .configurationUnreadable, .bootloaderIdentity, .noControllerLinked:
      #expect(state == .needsStep(.otherStep))
    }
  }

  @Test
  func unservedStateIgnoresPermissionAndDriver() {
    let input = ControllerReadinessInput(
      subject: .unserved(.noProtocolMatch),
      isPermissionMissing: true,
      needsDriverStep: true
    )
    #expect(ControllerReadiness.resolve(input) == .notSupported)
  }

  @Test
  func eachStateHasItsButtonAction() {
    #expect(ControllerReadiness.working.action == .openInputTest)
    #expect(ControllerReadiness.needsStep(.grantAccess).action == .openAccess)
    #expect(ControllerReadiness.needsStep(.setUpDriver).action == .setUpDriver)
    #expect(ControllerReadiness.needsStep(.otherStep).action == .openTroubleshooting)
    #expect(ControllerReadiness.notSupported.action == .openSupportedControllers)
  }

  @Test
  func notSupportedOpensSupportedControllersWikiPage() {
    #expect(
      ControllerReadinessAction.openSupportedControllers.wikiURL?.absoluteString
        == "https://github.com/xsyetopz/OpenJoystickDriver/wiki/Supported-Controllers"
    )
    #expect(ControllerReadinessAction.openInputTest.wikiURL == nil)
  }

  @Test
  func threeStatesDifferInSymbolShape() {
    let symbols = [
      ControllerReadiness.working, .needsStep(.grantAccess), .notSupported,
    ].map(\.symbolName)
    #expect(Set(symbols).count == 3)
    #expect(
      Set(symbols.map { $0.split(separator: ".").first.map(String.init) ?? "" }).count == 3
    )
  }

  @Test
  func everyStateTextExistsInCatalog() {
    let states: [ControllerReadiness] = [
      .working, .needsStep(.grantAccess), .needsStep(.setUpDriver), .needsStep(.otherStep),
      .notSupported,
    ]
    for state in states {
      for key in [state.titleKey, state.messageKey, state.actionTitleKey] {
        #expect(OJDLocalized.string(key) != key)
      }
    }
  }
}
