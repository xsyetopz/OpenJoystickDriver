import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct BoundedProcessRunnerTests {
  @Test
  func capturesMergedOutputAndExitStatus() throws {
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "printf stdout; printf stderr >&2; exit 7"]
    )

    #expect(result.terminationStatus == 7)
    #expect(result.output.contains("stdout"))
    #expect(result.output.contains("stderr"))
    #expect(!result.timedOut)
    #expect(!result.outputWasTruncated)
  }

  @Test
  func drainsFloodingOutputAndTerminatesAtDeadline() throws {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
      arguments: ["OpenJoystickDriver"],
      timeoutSeconds: 0.05,
      maximumOutputBytes: 1_024
    )
    let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt

    #expect(result.timedOut)
    #expect(result.output.utf8.count == 1_024)
    #expect(result.outputWasTruncated)
    #expect(elapsed < 1_500_000_000)
  }

  @Test
  func truncatesCapturedOutputWithoutChangingSuccessfulStatus() throws {
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
      arguments: [String(repeating: "x", count: 4_096)],
      maximumOutputBytes: 32
    )

    #expect(result.terminationStatus == 0)
    #expect(result.output == String(repeating: "x", count: 32))
    #expect(result.outputWasTruncated)
    #expect(!result.timedOut)
  }
}
