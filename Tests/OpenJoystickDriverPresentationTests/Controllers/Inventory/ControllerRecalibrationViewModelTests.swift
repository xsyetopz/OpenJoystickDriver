#if canImport(SwiftUI)
  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverTestSupport
  import Testing

  @testable import OpenJoystickDriverPresentation

  @MainActor
  struct ControllerRecalibrationViewModelTests {
    private let selector = ControllerReference.session(.fixture("pad"))

    @Test
    func stepSendsItsActionAndShowsThatValuesWereStored() async {
      let gateway = RecalibrationGatewayStub(
        result: ControllerRecalibrationResult(
          action: .rest,
          stored: ControllerCalibration(values: [.leftStickCenterX: 0.2])
        )
      )
      let model = ControllerRecalibrationViewModel(gateway: gateway)

      await model.run(.rest, for: selector)

      let requests = await gateway.requests
      #expect(requests.map(\.action) == [.rest])
      #expect(requests.map(\.controller) == [selector])
      #expect(model.message == OJDLocalized.string("ui.controllers.recalibrate.stored"))
      #expect(!model.isFailure)
      #expect(!model.isBusy)
    }

    @Test
    func untouchedTriggerIsNamedAsNotMoved() async {
      let gateway = RecalibrationGatewayStub(
        result: ControllerRecalibrationResult(
          action: .triggers,
          stored: ControllerCalibration(values: [.leftTriggerFull: 0.9]),
          unmoved: [.rightTrigger]
        )
      )
      let model = ControllerRecalibrationViewModel(gateway: gateway)

      await model.run(.triggers, for: selector)

      let named = OJDLocalized.formatted(
        "ui.controllers.recalibrate.unmoved",
        OJDLocalized.string("ui.controllers.calibration.rightTrigger")
      )
      #expect(model.message?.contains(named) == true)
    }

    @Test
    func stickAxesThatDidNotMoveNameTheirStickOnce() async {
      let gateway = RecalibrationGatewayStub(
        result: ControllerRecalibrationResult(
          action: .circle,
          unmoved: [.leftStickX, .leftStickY, .rightStickX]
        )
      )
      let model = ControllerRecalibrationViewModel(gateway: gateway)

      await model.run(.circle, for: selector)

      let named = OJDLocalized.formatted(
        "ui.controllers.recalibrate.unmoved",
        [
          OJDLocalized.string("ui.controllers.calibration.leftStick"),
          OJDLocalized.string("ui.controllers.calibration.rightStick"),
        ].joined(separator: ", ")
      )
      #expect(model.message == named)
    }

    @Test
    func resetReportsTheGyroOffsetOnlyWhenItWasCleared() async {
      for cleared in [true, false] {
        let gateway = RecalibrationGatewayStub(
          result: ControllerRecalibrationResult(
            action: .reset,
            cleared: [.leftStickCenterX],
            gyroOffsetCleared: cleared
          )
        )
        let model = ControllerRecalibrationViewModel(gateway: gateway)

        await model.run(.reset, for: selector)

        #expect(
          model.message
            == OJDLocalized.string(
              cleared
                ? "ui.controllers.recalibrate.resetDoneGyro"
                : "ui.controllers.recalibrate.resetDone"
            )
        )
      }
    }

    @Test
    func refusalShowsItsReasonAsAFailure() async {
      let gateway = RecalibrationGatewayStub(
        result: ControllerRecalibrationResult(action: .reset, failure: .noRecord)
      )
      let model = ControllerRecalibrationViewModel(gateway: gateway)

      await model.run(.reset, for: selector)

      #expect(model.message == OJDLocalized.string("ui.controllers.server.noRecord"))
      #expect(model.isFailure)
    }

    @Test
    func thrownErrorShowsAFailureAndFreesTheModel() async {
      let gateway = RecalibrationGatewayStub(result: nil)
      let model = ControllerRecalibrationViewModel(gateway: gateway)

      await model.run(.rest, for: selector)

      #expect(model.isFailure)
      #expect(model.message != nil)
      #expect(!model.isBusy)
    }
  }

  private actor RecalibrationGatewayStub: ControllerRecalibrationGateway {
    private let result: ControllerRecalibrationResult?
    private(set) var requests: [ControllerRecalibrationArguments] = []

    init(result: ControllerRecalibrationResult?) { self.result = result }

    func recalibrateController(
      _ controller: ControllerReference,
      action: ControllerRecalibrationAction
    ) throws -> ControllerRecalibrationResult {
      requests.append(.init(controller: controller, action: action))
      guard let result else { throw ApplicationServiceClientError.invalidResponse }
      return result
    }
  }
#endif
