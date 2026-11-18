import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct TimeoutTests {
  private struct Failure: Error, Equatable {}

  @Test(.timeLimit(.minutes(1)))
  func finishedOperationReturnsItsValue() async throws {
    let value = try await withTimeout(seconds: 30) { 7 }
    #expect(value == 7)
  }

  @Test(.timeLimit(.minutes(1)))
  func operationErrorIsRethrownAsItself() async {
    await #expect(throws: Failure.self) {
      try await withTimeout(seconds: 30) { () async throws -> Int in throw Failure() }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func missedDeadlineThrowsTimeoutErrorNamingSeconds() async {
    await #expect(throws: TimeoutError(seconds: 0.05)) {
      try await withTimeout(seconds: 0.05) {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return 1
      }
    }
  }
}
