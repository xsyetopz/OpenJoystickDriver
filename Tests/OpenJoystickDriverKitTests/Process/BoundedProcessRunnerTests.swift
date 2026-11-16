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

  @Test(.timeLimit(.minutes(1)))
  func childIsGivenDeadlineItWasAskedFor() throws {
    let deadlines = Locked<[TimeInterval]>([])
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/sleep"),
      arguments: ["3600"],
      environment: nil,
      timeoutSeconds: 7.5,
      maximumOutputBytes: 1_024
    ) { _, seconds in
      deadlines.withLock { $0.append(seconds) }
      return .timedOut
    }

    #expect(deadlines.withLock { $0 } == [7.5])
    #expect(result.timedOut)
  }

  @Test(.timeLimit(.minutes(1)))
  func drainsFloodingOutputAndTerminatesAtDeadline() throws {
    let result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
      arguments: ["OpenJoystickDriver"],
      timeoutSeconds: 0.05,
      maximumOutputBytes: 1_024
    )

    #expect(result.timedOut)
    #expect(result.output.utf8.count == 1_024)
    #expect(result.outputWasTruncated)
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
