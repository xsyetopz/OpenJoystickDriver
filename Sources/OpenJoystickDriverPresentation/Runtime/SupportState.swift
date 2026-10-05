import Foundation
import OpenJoystickDriverKit

struct SupportDiagnosticsPresentation: Sendable, Equatable {
  enum VirtualControllerOutputState: String, Sendable, Equatable {
    case available
    case unavailable
    case needsAttention
  }

  let virtualControllerOutputState: VirtualControllerOutputState
  let virtualControllerCount: Int

  init(payload: ApplicationServiceVirtualDeviceDiagnosticsPayload) {
    self.init(diagnostics: payload)
  }

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

  var virtualControllerOutputLabel: String {
    switch virtualControllerOutputState {
    case .available: return OJDLocalized.string("common.available")
    case .unavailable: return OJDLocalized.string("common.unavailable")
    case .needsAttention:
      return OJDLocalized.string("common.needsAttention")
    }
  }

  var virtualControllerOutputDetail: String {
    switch virtualControllerOutputState {
    case .available:
      return OJDLocalized.string(
        "debug.outputAvailable"
      )
    case .unavailable:
      return OJDLocalized.string("debug.outputOff")
    case .needsAttention:
      return OJDLocalized.string(
        "debug.outputNeedsAttention"
      )
    }
  }

  var virtualControllerCountLabel: String {
    OJDLocalized.plural(
      "debug.outputDevices",
      count: virtualControllerCount
    )
  }
}

enum RuntimeSupportDiagnosticsState: Sendable {
  case idle
  case loading
  case available(SupportDiagnosticsPresentation)
  case unavailable(String)
  case error(String)
}

enum RuntimeSupportReportState: Sendable {
  case idle
  case saving
  case saved
  case error(String)
}

enum RuntimeSupportLogsState: Sendable {
  case idle
  case saving
  case saved
  case error(String)
}
