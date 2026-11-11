import XCTest

@testable import WebRTCBridgeCore

/// Checks how ``BridgeCommandLine/parse(_:)`` splits the arguments.
final class BridgeCommandLineTests: XCTestCase {
  /// `--help` alone gives `.help`.
  func testHelpIsRecognisedAlone() {
    XCTAssertEqual(BridgeCommandLine.parse(["--help"]), .help)
  }

  /// `--help` gives `.help` whatever else the arguments hold.
  func testHelpWinsOverOtherArguments() {
    XCTAssertEqual(BridgeCommandLine.parse(["--role", "host", "--help"]), .help)
    XCTAssertEqual(BridgeCommandLine.parse(["--bogus", "--help"]), .help)
  }

  /// Values group by option name in order, and no arguments give no options.
  func testOptionsAreGroupedByName() {
    XCTAssertEqual(
      BridgeCommandLine.parse(["--role", "host", "--ice-server", "a", "--ice-server", "b"]),
      .options(["role": ["host"], "ice-server": ["a", "b"]])
    )
    XCTAssertEqual(BridgeCommandLine.parse([]), .options([:]))
  }

  /// An argument without `--`, or an option without a value, gives `.invalid`.
  func testABadArgumentIsInvalid() {
    XCTAssertEqual(BridgeCommandLine.parse(["role", "host"]), .invalid)
    XCTAssertEqual(BridgeCommandLine.parse(["--role"]), .invalid)
  }
}
