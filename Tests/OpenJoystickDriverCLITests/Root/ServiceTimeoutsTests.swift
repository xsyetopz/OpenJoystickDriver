import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct ServiceTimeoutsTests {
  @Test
  func contextFallsBackToKitTimeouts() {
    let context = CLIContext()

    #expect(context.requestTimeout == ServiceTimeouts.request)
    #expect(context.waitTimeout == ServiceTimeouts.wait)
    #expect(CLIContext(timeout: 2).requestTimeout == 2)
  }

  @Test
  func disconnectRequestOutlastsServiceBluetoothWait() {
    #expect(ServiceTimeouts.bluetoothDisconnectRequest > ServiceTimeouts.bluetoothDisconnect)
  }

  @Test
  func timeoutHelpNamesKitDefaults() {
    let help = Localization().formatted(
      "cli.shared.option.timeout",
      locale: Locale(identifier: "en_US_POSIX"),
      arguments: [ServiceTimeouts.request, ServiceTimeouts.wait]
    )

    #expect(help.contains("0.5"))
    #expect(help.contains("5"))
    #expect(!help.contains("%"))
  }

  @Test(arguments: [0.5, 1, 3600, Double.leastNonzeroMagnitude])
  func positiveFiniteNumberIsValidSeconds(seconds: Double) {
    #expect(isPositiveSeconds(seconds))
  }

  @Test(arguments: [0, -1, Double.nan, Double.infinity, -Double.infinity])
  func anythingElseIsNotValidSeconds(seconds: Double) {
    #expect(!isPositiveSeconds(seconds))
  }

  @Test(arguments: ["0", "-1", "nan", "inf", "x"])
  func environmentTimeoutUsesSameRule(value: String) {
    #expect(throws: (any Error).self) {
      try EnvironmentOptions(["OJD_TIMEOUT": value])
    }
  }

  @Test
  func positiveEnvironmentTimeoutIsAccepted() throws {
    #expect(try EnvironmentOptions(["OJD_TIMEOUT": "2.5"]).timeout == 2.5)
  }
}
