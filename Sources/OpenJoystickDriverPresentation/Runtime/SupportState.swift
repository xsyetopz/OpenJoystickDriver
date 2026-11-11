import Foundation
import OpenJoystickDriverKit

/// What the views show of the virtual device diagnostics: whether virtual controller output works
/// and how many OJD virtual controllers exist.
struct SupportDiagnosticsPresentation: Sendable, Equatable {
  /// Whether virtual controller output works.
  enum VirtualControllerOutputState: String, Sendable, Equatable {
    /// The output is on.
    case available
    /// The output is off.
    case unavailable
    /// The output reports an error.
    case needsAttention
  }

  /// Whether virtual controller output works.
  let virtualControllerOutputState: VirtualControllerOutputState
  /// How many OJD user space virtual controllers the system lists.
  let virtualControllerCount: Int

  /// Creates the presentation from the diagnostics.
  init(payload: ApplicationServiceVirtualDeviceDiagnosticsPayload) {
    self.init(diagnostics: payload)
  }

  /// Creates the presentation from the diagnostics.
  init(diagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload) {
    if diagnostics.userSpaceVirtualDeviceStatus.isError {
      virtualControllerOutputState = .needsAttention
    } else if diagnostics.userSpaceVirtualDeviceEnabled {
      virtualControllerOutputState = .available
    } else {
      virtualControllerOutputState = .unavailable
    }
    virtualControllerCount = diagnostics.hidGamepads.count(where: \.isOJDUserSpace)
  }

  /// The label of the output state.
  var virtualControllerOutputLabel: String {
    switch virtualControllerOutputState {
    case .available: return OJDLocalized.string("status.available")
    case .unavailable: return OJDLocalized.string("status.unavailable")
    case .needsAttention:
      return OJDLocalized.string("status.needsAttention")
    }
  }

  /// The sentence that describes the output state.
  var virtualControllerOutputDetail: String {
    switch virtualControllerOutputState {
    case .available:
      return OJDLocalized.string(
        "ui.debug.outputAvailable"
      )
    case .unavailable:
      return OJDLocalized.string("ui.debug.outputOff")
    case .needsAttention:
      return OJDLocalized.string(
        "ui.debug.outputNeedsAttention"
      )
    }
  }

  /// The phrase for the number of virtual controllers.
  var virtualControllerCountLabel: String {
    OJDLocalized.plural(
      "ui.debug.outputDevices",
      count: virtualControllerCount
    )
  }
}

/// The load state of the virtual device diagnostics.
enum RuntimeSupportDiagnosticsState: Sendable {
  /// Nothing is read.
  case idle
  /// A read is running.
  case loading
  /// The diagnostics are loaded; the value holds them.
  case available(SupportDiagnosticsPresentation)
  /// The service cannot be reached; the value is the message.
  case unavailable(String)
  /// The read failed; the value is the message.
  case error(String)
}

/// Where saving the support report is.
enum RuntimeSupportReportState: Sendable {
  /// No save runs.
  case idle
  /// The report is being written.
  case saving
  /// The report is saved.
  case saved
  /// Saving failed; the value is the message.
  case error(String)
}

/// Where saving the logs is.
enum RuntimeSupportLogsState: Sendable {
  /// No save runs.
  case idle
  /// The logs are being written.
  case saving
  /// The logs are saved.
  case saved
  /// Saving failed; the value is the message.
  case error(String)
}
