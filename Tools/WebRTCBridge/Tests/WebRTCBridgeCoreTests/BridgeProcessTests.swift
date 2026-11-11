import Testing

/// Runs the built `ojd-webrtc-bridge` binary and checks its usage output and exit status.
final class BridgeProcessTests {
  /// The exit status and the captured output of one run.
  private struct Result {
    /// The exit status.
    let status: Int32
    /// Standard output as text.
    let output: String
    /// Standard error as text.
    let error: String
  }

  /// Runs the binary next to the test bundle with the arguments and waits for it to exit.
  private func run(_ arguments: [String]) throws -> Result {
    let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
    let binary = products.appendingPathComponent("ojd-webrtc-bridge")
    #expect(
      FileManager.default.isExecutableFile(atPath: binary.path),
      "the bridge is not built next to the test bundle at \(binary.path)"
    )
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Result(
      status: process.terminationStatus,
      output: String(bytes: outputData, encoding: .utf8) ?? "",
      error: String(bytes: errorData, encoding: .utf8) ?? ""
    )
  }

  /// `--help` prints the usage to standard output and exits with status 0.
  @Test
  func helpPrintsUsageToStandardOutputAndExitsZero() throws {
    let result = try run(["--help"])
    #expect(result.status == 0)
    #expect(result.output.hasPrefix("usage: ojd-webrtc-bridge"), Comment(rawValue: result.output))
    #expect(result.error.isEmpty)
  }

  /// A bad argument prints the usage to standard error and exits with status 1.
  @Test
  func aBadArgumentPrintsUsageToStandardErrorAndExitsNonZero() throws {
    let result = try run(["--bad"])
    #expect(result.status == 1)
    #expect(result.error.hasPrefix("usage: ojd-webrtc-bridge"), Comment(rawValue: result.error))
    #expect(result.output.isEmpty)
  }
}
