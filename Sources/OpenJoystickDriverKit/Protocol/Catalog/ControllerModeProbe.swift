public import Foundation

/// A read-only behavioral probe: one read of a feature report whose answer, stall, or byte pattern
/// tells a mode apart.
///
/// A probe has no write; ``ControllerModeProbeReader`` offers none either.
public struct ControllerModeProbe: Equatable, Sendable {
  /// What the read must show for the probe to hold.
  public enum Expectation: Equatable, Sendable {
    /// The device answers the read.
    case answers
    /// The device refuses the read.
    case stalls
    /// The reply holds `expected` starting at `offset`.
    case bytes(offset: Int, expected: [UInt8])
  }

  /// What one reply says about a probe.
  public enum Verdict: Equatable, Sendable {
    /// The reply meets the expectation.
    case satisfied
    /// The reply does not meet the expectation.
    case unsatisfied
    /// The device gave no usable reply, so the probe says nothing either way.
    case inconclusive
  }

  /// The ID of the feature report to read.
  public let reportID: UInt8
  /// The number of bytes to read.
  public let length: Int
  /// What the reply must show.
  public let expectation: Expectation

  /// Creates a probe of one feature report.
  public init(reportID: UInt8, length: Int, expectation: Expectation) {
    self.reportID = reportID
    self.length = length
    self.expectation = expectation
  }

  /// The read the probe performs.
  var request: PhysicalHIDFeatureReadRequest {
    PhysicalHIDFeatureReadRequest(reportID: reportID, length: length)
  }

  /// Only the device's own refusal (`PhysicalHIDFailure.declined`: a stalled control pipe, or a
  /// request it does not support) is a stall.
  ///
  /// A DualShock 3 clone stalls its pipe for report `0xEF`; both refusals count, because either
  /// says the device lacks the report. A timeout, an unavailable route, and every other failure
  /// (not open, no device, aborted, not permitted, exclusive access) say nothing about the device,
  /// so they are inconclusive.
  func verdict(for result: PhysicalHIDReportResult<Data>) -> Verdict {
    switch result {
    case .success(let data):
      switch expectation {
      case .answers: return .satisfied
      case .stalls: return .unsatisfied
      case .bytes(let offset, let expected):
        let reply = [UInt8](data)
        guard reply.count >= offset + expected.count else { return .unsatisfied }
        return Array(reply[offset..<offset + expected.count]) == expected
          ? .satisfied : .unsatisfied
      }
    case .unavailable:
      return .inconclusive
    case .failed(.declined):
      return expectation == .stalls ? .satisfied : .unsatisfied
    case .failed(.timedOut), .failed(.busy), .failed(.notResponding), .failed(.hostStatus):
      return .inconclusive
    }
  }
}

/// The only access a probe has to a controller: a feature-report read.
///
/// There is no write requirement, so a probe cannot change a controller.
public protocol ControllerModeProbeReader: Sendable {
  /// Reads one feature report from the controller.
  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
}
