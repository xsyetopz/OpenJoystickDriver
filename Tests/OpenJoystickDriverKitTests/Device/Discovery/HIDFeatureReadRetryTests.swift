import Testing

@testable import OpenJoystickDriverKit

struct HIDFeatureReadRetryTests {
  @Test func successfulReplyStopsRetries() async {
    let attempts = FeatureAttemptRecorder([.retry, .accepted, .retry])
    let result = await HIDFeatureReadRetry.run(delayNanoseconds: 0) { await attempts.next() }
    #expect(result == .accepted)
    #expect(await attempts.count == 2)
  }

  @Test func malformedOrUnavailableRepliesExhaustAtThreeAttempts() async {
    let attempts = FeatureAttemptRecorder([])
    let result = await HIDFeatureReadRetry.run(maximumAttempts: 100, delayNanoseconds: 0) {
      await attempts.next()
    }
    #expect(result == .retry)
    #expect(await attempts.count == 3)
  }

  @Test func pipelineLossStopsImmediately() async {
    let attempts = FeatureAttemptRecorder([.retry, .stopped, .accepted])
    let result = await HIDFeatureReadRetry.run(delayNanoseconds: 0) { await attempts.next() }
    #expect(result == .stopped)
    #expect(await attempts.count == 2)
  }

  @Test func cancellationCannotSendAnotherAttempt() async {
    let attempts = FeatureAttemptRecorder([])
    let task = Task {
      await HIDFeatureReadRetry.run(delayNanoseconds: 0) {
        let result = await attempts.next()
        withUnsafeCurrentTask { $0?.cancel() }
        return result
      }
    }
    #expect(await task.value == .stopped)
    #expect(await attempts.count == 1)
  }

  @Test func nonConsumerIsLimitedToOneRead() async {
    let attempts = FeatureAttemptRecorder([])
    #expect(await HIDFeatureReadRetry.run(maximumAttempts: 1, delayNanoseconds: 0) {
      await attempts.next()
    } == .retry)
    #expect(await attempts.count == 1)
  }
}

private actor FeatureAttemptRecorder {
  let outcomes: [HIDFeatureReadAttempt]
  var count = 0

  init(_ outcomes: [HIDFeatureReadAttempt]) { self.outcomes = outcomes }

  func next() -> HIDFeatureReadAttempt {
    defer { count += 1 }
    return count < outcomes.count ? outcomes[count] : .retry
  }
}
