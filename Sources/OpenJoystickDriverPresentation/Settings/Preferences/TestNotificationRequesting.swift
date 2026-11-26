#if canImport(AppKit) && canImport(SwiftUI)

  import Combine
  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The app's side of the test notification: the request to the service and the report back.
  protocol TestNotificationRequesting: Sendable {
    /// Asks the service to announce a test notification and returns how it ended.
    func requestTestNotification() async throws -> TestNotificationOutcome
    /// Answers an announcement this app took from the service.
    func reportTestNotification(
      _ announcement: UUID,
      outcome: TestNotificationOutcome
    )
      async throws -> Bool
  }

  extension ApplicationServiceClientGateway: TestNotificationRequesting {}

#endif
