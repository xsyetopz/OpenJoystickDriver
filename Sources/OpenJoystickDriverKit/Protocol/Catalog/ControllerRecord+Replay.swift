import Foundation

/// The state a record's parser reaches after it replays captured input reports.
public struct ControllerRecordReplay: Equatable, Sendable {
  /// The controller's full state after the last report that carried input.
  public let state: ControllerState
  /// How many of the replayed reports carried input; the others were acknowledgements, status
  /// frames, or partial transfers that the parser ignores.
  public let inputReports: Int
}

/// Why a record cannot replay a capture.
public enum ControllerRecordReplayError: Error, Equatable, Sendable {
  /// The record's family and variant have no parser that runs without a device.
  case noParser
  /// The parser rejected the report at this zero-based position.
  case invalidReport(index: Int)
  /// No report carried input.
  case noInput
}

extension ControllerRecord {
  /// Parses `reports` in order through the parser the runtime builds for this record.
  ///
  /// Each report is the bytes of one received packet, as `PacketLogEntry.hex` holds them. A
  /// driver keeps no state from a device, so the replay builds a fresh driver and stamps the
  /// reports 1 ms apart.
  public func replay(reports: [[UInt8]]) throws -> ControllerRecordReplay {
    let variant =
      profile.physicalProtocolVariant
      ?? (profile.physicalProtocolID.variants.contains(.usb) ? .usb : nil)
    guard
      case .success(let driver) = ProtocolDriverRegistry.makeUnobservedDriver(
        protocolID: profile.physicalProtocolID,
        variant: variant,
        record: profile,
        identifier: DeviceIdentifier(
          vendorID: identity.vendorID,
          productID: identity.productID
        ),
        transportProfile: profile.transportProfile
      )
    else { throw ControllerRecordReplayError.noParser }
    var state: ControllerState?
    var inputReports = 0
    for (index, report) in reports.enumerated() {
      let event: ControllerEvent?
      do {
        event = try driver.parse(
          report: Data(report),
          receivedAt: MonotonicTimestamp(nanoseconds: UInt64(index + 1) * 1_000_000)
        )
      } catch { throw ControllerRecordReplayError.invalidReport(index: index) }
      guard let event else { continue }
      state = event.state
      inputReports += 1
    }
    guard let state else { throw ControllerRecordReplayError.noInput }
    return ControllerRecordReplay(state: state, inputReports: inputReports)
  }
}
