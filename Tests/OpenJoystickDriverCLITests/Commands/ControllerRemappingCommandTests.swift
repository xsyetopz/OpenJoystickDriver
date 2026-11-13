import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ControllerRemappingCommandTests {
  @Test
  func calibrateSendsActionAndReportsStatus() async throws {
    let status = Data(
      (#"{"hasMotionBaseline":false,"isCollecting":true,"#
        + #""offsetDegreesPerSecond":{"x":0.5,"y":0,"z":-0.25}}"#).utf8
    )
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ]) { method, _ in
      method == .remappingMotionCalibration ? status : nil
    }

    let result = await service.run(["controller", "calibrate", token("pad-1"), "start", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["controller"] as? String == token("pad-1"))
    #expect(json["collecting"] as? Bool == true)
    #expect(json["calibrated"] as? Bool == false)
    let arguments = try #require(service.arguments(of: .remappingMotionCalibration).first)
    let sent = try JSONDecoder().decode(
      ApplicationServiceMotionCalibrationArguments.self,
      from: arguments
    )
    #expect(sent.command == .start)
    #expect(sent.controller == .session(.fixture("pad-1")))
  }

  @Test(arguments: [
    ApplicationServiceRemappingRPCError.Code.motionGyroNotSelected,
    .motionProfileInactive,
    .motionSessionChanged,
  ])
  func calibrateExplainsEachServiceRefusalByItsOwnCode(
    code: ApplicationServiceRemappingRPCError.Code
  ) {
    let error = ApplicationServiceRemappingRPCError(code: code, message: "service text")

    let failure =
      ControllerCalibrateCommand.failure(error, device: .fixture(id: "pad-1")) as? CLIFailure

    #expect(failure?.id == code.errorCode)
    #expect(failure?.message == code.errorCode.localizedExplanation)
  }

  @Test
  func calibrateNamesControllerWhenServiceCannotReachIt() {
    let device = ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    let error = ApplicationServiceRemappingRPCError(
      code: .controllerUnavailable,
      message: "The selected controller is unavailable."
    )

    let failure = ControllerCalibrateCommand.failure(error, device: device) as? CLIFailure

    #expect(failure?.id == .controllerUnavailable)
    #expect(failure?.message.contains(device.name) == true)
  }

  @Test
  func pairAndUnpairJoinAndSeparateTwoJoyCons() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pair")])
    let service = try FakeService(
      devices: [
        ApplicationServiceDeviceDescription.fixture(
          id: "left-1",
          vendorID: 0x057E,
          productID: 0x2006
        ),
        ApplicationServiceDeviceDescription.fixture(
          id: "right-1",
          vendorID: 0x057E,
          productID: 0x2007
        ),
      ],
      respond: library.respond
    )

    let paired = await service.run([
      "controller", "pair", "057E:2006", token("right-1"), "--profile", "Pair", "--json",
    ])
    let unpaired = await service.run(["controller", "unpair", token("right-1"), "--json"])
    let missing = await service.run(["controller", "unpair", token("right-1")])

    #expect(paired.code == 0, "\(paired.standardError)")
    let pair = try paired.json()
    #expect(pair["left"] as? String == token("left-1"))
    #expect(pair["right"] as? String == token("right-1"))
    #expect(pair["profile"] as? String == "Pair")
    #expect(unpaired.code == 0, "\(unpaired.standardError)")
    #expect(try unpaired.json()["session"] as? String == pair["session"] as? String)
    #expect(library.snapshot.joyConPairs.isEmpty)
    #expect(missing.code == 1)
  }
}
