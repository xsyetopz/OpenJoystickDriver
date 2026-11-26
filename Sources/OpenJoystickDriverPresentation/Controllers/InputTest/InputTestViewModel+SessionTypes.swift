#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  extension InputTestViewModel {
    /// Where the sampling of the controller's input is.
    enum SessionState: Equatable {
      /// No sampling runs.
      case idle
      /// The first sample is awaited.
      case starting
      /// Samples arrive and every control is at rest.
      case receiving
      /// Samples arrive and a control has left its rest value.
      case live
      /// Samples stopped arriving after some had come.
      case stale
      /// The controller is not connected.
      case disconnected
      /// Reading the input needs a permission that is not granted.
      case permissionRequired
      /// No sample ever arrived.
      case unavailable
      /// The session failed; the status reads Failed.
      case error
    }

    /// The output test.
    enum OutputOperation: Equatable {
      /// The rumble test.
      case rumble
      /// The player indicator.
      case playerIndicator
      /// The color.
      case color
      /// The brightness.
      case brightness
    }

    /// Where the latest output test is.
    enum OutputState: Equatable {
      /// No output test runs.
      case idle
      /// The output test runs.
      case running(OutputOperation)
      /// The controller received the output.
      case succeeded(OutputOperation)
      /// The output failed.
      case failed(OutputOperation)
    }

    /// Waits for a number of nanoseconds.
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    /// Why an output test is not sent.
    enum OutputRefusal {
      /// No controller is connected.
      case notConnected
      /// The controller has no such output.
      case unsupported

      /// The localization key of the message.
      var messageKey: String {
        switch self {
        case .notConnected: "ui.inputTest.outputNotConnected"
        case .unsupported: "ui.inputTest.outputUnsupported"
        }
      }
    }
  }

#endif
