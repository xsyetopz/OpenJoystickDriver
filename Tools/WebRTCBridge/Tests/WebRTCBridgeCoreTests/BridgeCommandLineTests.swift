import Testing

@testable import WebRTCBridgeCore

/// Checks how ``BridgeCommandLine/parse(_:)`` splits the arguments.
final class BridgeCommandLineTests {
  /// `--help` alone gives `.help`.
  @Test
  func helpRecognisedAlone() {
    #expect(BridgeCommandLine.parse(["--help"]) == .help)
  }

  /// `--help` gives `.help` whatever else the arguments hold.
  @Test
  func helpWinsOverOtherArguments() {
    #expect(BridgeCommandLine.parse(["--role", "host", "--help"]) == .help)
    #expect(BridgeCommandLine.parse(["--bogus", "--help"]) == .help)
  }

  /// Values group by option name in order, and no arguments give no options.
  @Test
  func optionsGroupedByName() {
    #expect(
      BridgeCommandLine.parse(["--role", "host", "--ice-server", "a", "--ice-server", "b"])
        == .options(["role": ["host"], "ice-server": ["a", "b"]])
    )
    #expect(BridgeCommandLine.parse([]) == .options([:]))
  }

  /// An argument without `--`, or an option without a value, gives `.invalid`.
  @Test
  func badArgumentInvalid() {
    #expect(BridgeCommandLine.parse(["role", "host"]) == .invalid)
    #expect(BridgeCommandLine.parse(["--role"]) == .invalid)
  }
}
