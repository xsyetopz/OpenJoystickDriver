import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct ServiceTimeoutsTests {
  @Test
  func theContextFallsBackToTheKitTimeouts() {
    let context = CLIContext()

    #expect(context.requestTimeout == ServiceTimeouts.request)
    #expect(context.waitTimeout == ServiceTimeouts.wait)
    #expect(CLIContext(timeout: 2).requestTimeout == 2)
  }

  @Test
  func aDisconnectRequestOutlastsTheServiceBluetoothWait() {
    #expect(ServiceTimeouts.bluetoothDisconnectRequest > ServiceTimeouts.bluetoothDisconnect)
  }

  @Test
  func theTimeoutHelpNamesTheKitDefaults() {
    let help = Localization().formatted(
      "cli.option.timeout",
      locale: Locale(identifier: "en_US_POSIX"),
      arguments: [ServiceTimeouts.request, ServiceTimeouts.wait]
    )

    #expect(help.contains("0.5"))
    #expect(help.contains("5"))
    #expect(!help.contains("%"))
  }

  @Test(arguments: [0.5, 1, 3600, Double.leastNonzeroMagnitude])
  func aPositiveFiniteNumberIsValidSeconds(seconds: Double) {
    #expect(isPositiveSeconds(seconds))
  }

  @Test(arguments: [0, -1, Double.nan, Double.infinity, -Double.infinity])
  func anythingElseIsNotValidSeconds(seconds: Double) {
    #expect(!isPositiveSeconds(seconds))
  }

  @Test(arguments: ["0", "-1", "nan", "inf", "x"])
  func theEnvironmentTimeoutUsesTheSameRule(value: String) {
    #expect(throws: (any Error).self) {
      try EnvironmentFallback(["OJD_TIMEOUT": value])
    }
  }

  @Test
  func aPositiveEnvironmentTimeoutIsAccepted() throws {
    #expect(try EnvironmentFallback(["OJD_TIMEOUT": "2.5"]).timeout == 2.5)
  }
}
