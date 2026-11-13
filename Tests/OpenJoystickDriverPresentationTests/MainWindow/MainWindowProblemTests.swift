import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowProblemTests {
  private func status(inputRead: PermissionManager.AccessState) -> RuntimeStatusState {
    .available(
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          inputRead: inputRead,
          inputInject: .granted,
          connectedDevices: [],
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready")
        )
      )
    )
  }

  private static let failure = SystemExtensionRequestFailure(
    domain: "OSSystemExtensionErrorDomain",
    code: 4,
    text: "No"
  )

  private func permissions(_ read: RuntimePermissionState) -> RuntimePermissionLoadState {
    .available(RuntimePermissionSummary(inputRead: read, inputInject: .granted))
  }

  @Test
  func healthyAppHasNoProblemAndNoBanner() {
    #expect(
      MainWindowProblem.current(
        permissions: permissions(.granted),
        status: status(inputRead: .granted),
        driver: .active,
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: nil
      ).isEmpty
    )
    #expect(
      MainWindowProblem.current(
        permissions: .loading,
        status: .loading,
        driver: .checking,
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: nil
      ).isEmpty
    )
  }

  @Test
  func accessProblemFollowsSameRuleAsStatusItemAndAccessArea() {
    let cases: [(RuntimePermissionLoadState, RuntimeStatusState, Bool)] = [
      (permissions(.granted), status(inputRead: .denied), false),
      (permissions(.denied), status(inputRead: .granted), true),
      (permissions(.unknown), .loading, true),
      (.requesting, status(inputRead: .unknown), false),
      (.loading, status(inputRead: .unknown), false),
      (.error("failed"), status(inputRead: .unknown), true),
      (.unavailable, status(inputRead: .denied), true),
      (.unavailable, .unavailable("down"), false),
    ]
    for (reading, payload, isMissing) in cases {
      let problems = MainWindowProblem.current(
        permissions: reading,
        status: payload,
        driver: .active,
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: nil
      )
      #expect(problems.contains(.accessMissing) == isMissing, "\(reading)")
    }
    #expect(
      !MainWindowProblem.current(
        permissions: permissions(.granted),
        status: status(inputRead: .denied),
        driver: .active,
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: nil
      ).contains(.accessMissing)
    )
  }

  @Test
  func problemsRunFromServiceToDriverToAccess() {
    #expect(
      MainWindowProblem.current(
        permissions: .unavailable,
        status: .unavailable("down"),
        driver: .needsApproval,
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: nil
      )
        == [.service(.stopped, "down"), .driver(.needsApproval)]
    )
    #expect(
      MainWindowProblem.current(
        permissions: permissions(.denied),
        status: status(inputRead: .denied),
        driver: .failed(Self.failure),
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: nil
      )
        == [.driver(.failed(Self.failure)), .accessMissing]
    )
  }

  @Test
  func eachProblemNamesItsAction() {
    #expect(MainWindowProblem.service(.stopped, "down").action == .retryService)
    #expect(MainWindowProblem.driver(.needsApproval).action == .openDriverApproval)
    #expect(MainWindowProblem.driver(.needsActivation).action == .repairDriver)
    #expect(MainWindowProblem.driver(.invalid).action == nil)
    #expect(MainWindowProblem.driver(.unavailable("probe failed")).action == nil)
    #expect(MainWindowProblem.driver(.missingEmbedded).action == nil)
    #expect(MainWindowProblem.accessMissing.action == .showAccess)
  }

  @Test
  func driverProblemNeedsConnectedControllerRoutedThroughExtension() {
    for connected in [false, true] {
      let problems = MainWindowProblem.current(
        permissions: permissions(.granted),
        status: status(inputRead: .granted),
        driver: .needsActivation,
        extensionRouteConnected: connected,
        liveUpdatesFallbackReason: nil,
        listenerFailure: nil
      )
      #expect(problems.contains(.driver(.needsActivation)) == connected)
    }
    #expect(!RuntimeStatusState.loading.hasExtensionRouteController)
  }

  @Test
  func runningRequestShowsProgressWithDisabledButton() {
    let problem = MainWindowProblem.driver(.running)
    #expect(problem.detailKey == "ui.setup.runningDetail")
    #expect(problem.actionTitleKey == "ui.setup.repairRunning")
    #expect(!problem.isActionEnabled)
    #expect(MainWindowProblem.driver(.needsActivation).isActionEnabled)
  }

  @Test
  func eachRequestOutcomeHasItsOwnTextAndButton() {
    let cases: [(SystemExtensionSetupState, String, MainWindowProblemAction?)] = [
      (.needsApproval, "platform.macos.ui.setup.approvalDetail", .openDriverApproval),
      (.cancelled, "ui.setup.cancelledDetail", .repairDriver),
      (.timedOut, "ui.setup.timedOutDetail", .repairDriver),
      (.failed(Self.failure), "ui.setup.failedDetail", .repairDriver),
      (.unavailable("probe failed"), "ui.setup.unavailableDetail", nil),
      (.missingEmbedded, "ui.setup.missingDetail", nil),
      (.invalid, "ui.setup.invalidDetail", nil),
    ]
    for (state, detailKey, action) in cases {
      let problem = MainWindowProblem.driver(state)
      #expect(problem.detailKey == detailKey, "\(state)")
      #expect(problem.action == action, "\(state)")
      #expect((problem.actionTitleKey == nil) == (action == nil), "\(state)")
    }
  }

  @Test
  func onlyProblemsThatNeedServiceOrReinstallAreFailures() {
    #expect(MainWindowProblem.service(.stopped, "down").isFailure)
    #expect(MainWindowProblem.driver(.missingEmbedded).isFailure)
    #expect(!MainWindowProblem.driver(.needsApproval).isFailure)
    #expect(!MainWindowProblem.accessMissing.isFailure)
  }

  @Test
  func pollingInsteadOfLiveUpdatesIsQuietProblemWithItsReason() {
    let problems = MainWindowProblem.current(
      permissions: permissions(.granted),
      status: status(inputRead: .granted),
      driver: .active,
      extensionRouteConnected: true,
      liveUpdatesFallbackReason: .timeout,
      listenerFailure: nil
    )
    #expect(problems == [.liveUpdatesPolling(.timeout)])
    #expect(problems.first?.isFailure == false)
    #expect(problems.first?.action == nil)
    #expect(problems.first?.titleKey == "ui.banner.liveUpdates.title")
    #expect(problems.first?.detailKey == "ui.banner.liveUpdates.detail.timeout")
  }

  @Test
  func unreadableOverrideStoreBannerProblemNotControlProblem() {
    let unreadable = RuntimeStatusState.available(
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          inputRead: .granted,
          inputInject: .granted,
          connectedDevices: [],
          virtualHIDProfileOverrideError: "unsupported-schema"
        )
      )
    )
    let problems = MainWindowProblem.current(
      permissions: permissions(.granted),
      status: unreadable,
      driver: .active,
      extensionRouteConnected: true,
      liveUpdatesFallbackReason: nil,
      listenerFailure: nil
    )
    #expect(problems.count == 1)
    #expect(problems.first?.titleKey == "ui.virtualProfile.title")
    #expect(problems.first?.isFailure == false)
    #expect(problems.first?.action == nil)
    guard case .virtualProfileStore(let message) = problems.first else {
      Issue.record("expected the override store problem")
      return
    }
    #expect(message.contains("unsupported-schema"))
  }

  @Test
  func emptyOrMissingValueShowsNone() {
    #expect(OJDValue(nil).displayText == OJDLocalized.string("status.none"))
    #expect(OJDValue("").displayText == OJDLocalized.string("status.none"))
    #expect(OJDValue(nil).accessibilityKey == "status.none")
    #expect(OJDValue("Xbox One").displayText == "Xbox One")
    #expect(OJDValue("Xbox One").accessibilityKey == nil)
  }

  @Test
  func reportedValuesWithoutContentShowNone() {
    #expect(OJDValue.reported("  \n") == .none)
    #expect(OJDValue.reported(nil) == .none)
    #expect(OJDValue.reported(" USB ") == .text("USB"))
    #expect(OJDValue.endpoint(0) == .none)
    #expect(OJDValue.endpoint(0x82) == .text("0x82"))
    #expect(OJDValue.usbIdentifier(vendorID: 0, productID: 0) == .none)
    #expect(OJDValue.usbIdentifier(vendorID: 0x3537, productID: 0x1010) == .text("3537:1010"))
    #expect(OJDValue.usbIdentifier(vendorID: 0, productID: 5) == .text("0000:0005"))
  }

  @Test
  func sentencesReadMissingValueAsWordAndNotHyphen() {
    #expect(OJDValue.none.spokenText == OJDLocalized.string("status.none"))
    #expect(OJDValue.none.spokenText != "-")
    #expect(OJDValue.text("x").spokenText == "x")
  }

  @Test
  func serialNumberStartsHiddenAndEyeTogglesIt() {
    var visibility = SerialNumberVisibility()
    let serial = OJDValue.text("ABC123")
    #expect(visibility.presentation(of: serial).isObscured)
    #expect(visibility.presentation(of: serial).displayText != "ABC123")
    #expect(
      visibility.presentation(of: serial).spokenText
        == OJDLocalized.string("ui.controllers.serial.hidden")
    )
    #expect(visibility.presentation(of: serial).toggleSymbolName == "eye")
    visibility.toggle()
    #expect(visibility.presentation(of: serial).displayText == "ABC123")
    #expect(visibility.presentation(of: serial).spokenText == "ABC123")
    #expect(visibility.presentation(of: serial).toggleSymbolName == "eye.slash")
    visibility.toggle()
    #expect(visibility.presentation(of: serial).isObscured)
  }

  @Test
  func missingSerialNumberShowsNoneWithoutEye() {
    let presentation = SerialNumberVisibility().presentation(of: .none)
    #expect(!presentation.canToggle)
    #expect(!presentation.isObscured)
    #expect(presentation.displayText == OJDLocalized.string("status.none"))
  }

  @Test
  func bannerRowWithButtonOffersFixOfMatchingControllerCard() {
    #expect(MainWindowProblem.driver(.needsApproval).offersFix(of: .setUpDriver))
    #expect(MainWindowProblem.driver(.needsActivation).offersFix(of: .setUpDriver))
    #expect(MainWindowProblem.accessMissing.offersFix(of: .openAccess))
  }

  @Test
  func driverRowWithoutButtonLeavesCardsButton() {
    #expect(!MainWindowProblem.driver(.missingEmbedded).offersFix(of: .setUpDriver))
    #expect(!MainWindowProblem.driver(.invalid).offersFix(of: .setUpDriver))
  }

  @Test
  func bannerRowOffersOnlyFixOfItsOwnProblem() {
    #expect(!MainWindowProblem.accessMissing.offersFix(of: .setUpDriver))
    #expect(!MainWindowProblem.driver(.needsApproval).offersFix(of: .openAccess))
    #expect(!MainWindowProblem.accessMissing.offersFix(of: .openInputTest))
    #expect(!MainWindowProblem.service(.stopped, "").offersFix(of: .openTroubleshooting))
  }
}
