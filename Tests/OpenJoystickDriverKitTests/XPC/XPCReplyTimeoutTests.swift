import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct XPCReplyTimeoutTests {
  @Test
  func firstReplyWinsWhenAServiceRepliesTwice() async throws {
    let value: Int = try await waitForXPCReply(timeoutSeconds: 1) { finish in
      finish(.success(7))
      finish(.success(8))
    }

    #expect(value == 7)
  }

  @Test
  func missingReplyTimesOutAndIgnoresALateReply() async throws {
    let startedAt = Date()
    var receivedTimeout = false

    do {
      let _: Int = try await waitForXPCReply(timeoutSeconds: 0.02) { finish in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) {
          finish(.success(9))
        }
      }
      Issue.record("Expected XPCError.timeout")
    } catch let error as XPCError {
      if case .timeout = error {
        receivedTimeout = true
      } else {
        Issue.record("Expected timeout, received \(error)")
      }
    } catch {
      Issue.record("Expected XPCError.timeout, received \(error)")
    }

    #expect(receivedTimeout)
    #expect(Date().timeIntervalSince(startedAt) < 1)
    try await Task.sleep(nanoseconds: 80_000_000)
  }

  @Test
  func explicitFailureWinsBeforeTheDeadline() async throws {
    do {
      let _: Int = try await waitForXPCReply(timeoutSeconds: 1) { finish in
        finish(.failure(XPCError.invalidResponse))
      }
      Issue.record("Expected XPCError.invalidResponse")
    } catch let error as XPCError {
      if case .invalidResponse = error {
        return
      }
      Issue.record("Expected invalidResponse, received \(error)")
    } catch {
      Issue.record("Expected XPCError.invalidResponse, received \(error)")
    }
  }
}
