/// When a HID startup write is sent.
public enum StartupPhase: String, CaseIterable, Sendable {
  /// With the driver's own startup writes, before activation, paced by the startup interval.
  case startup = "Startup"
  /// After the driver's activation writes.
  case activation = "Activation"
}

/// One fixed HID report sent when OJD starts a controller it owns.
///
/// A controller record carries them for a pad whose enable sequence never changes; a protocol
/// description carries the ones every controller of its family needs, and a record's own writes
/// replace them.
public struct RecordStartupWrite: Equatable, Sendable {
  /// Transports a startup write may be limited to; OJD reaches a HID controller over these.
  static let transports: [PhysicalTransport] = [.usb, .bluetoothClassic, .bluetoothLE]
  /// The longest report a startup write sends.
  static let lengthRange = 2...128

  /// The report the write sends.
  public let report: ControllerTemplateReport
  /// Every byte after a nonzero report ID, or the whole report when the ID is zero.
  public let bytes: [UInt8]
  /// The wait before this write.
  ///
  /// Nil waits the startup interval before a `startup` write and nothing before an `activation`
  /// write.
  public let delayMilliseconds: Int?
  /// The only transport this write is sent on; nil sends it on every transport.
  public let transport: PhysicalTransport?
  /// When the write is sent.
  public let phase: StartupPhase
  /// When set, the last four bytes of the report are replaced by the CRC-32 that Sony Bluetooth
  /// reports carry, seeded with this HID transaction header byte.
  public let crc32Seed: UInt8?
  /// Which controllers a protocol description's write is for; always for a record's write.
  public let condition: StartupWriteCondition

  /// Fails unless the report is an output or feature report of 2...128 bytes, `bytes` fills every
  /// writable byte of it, the delay is 0...1000 ms, the transport is one a HID controller uses,
  /// and a CRC report has room for its trailer.
  init(
    report: ControllerTemplateReport,
    bytes: [UInt8],
    delayMilliseconds: Int? = nil,
    transport: PhysicalTransport? = nil,
    phase: StartupPhase = .activation,
    crc32Seed: UInt8? = nil,
    condition: StartupWriteCondition = .always
  )
    throws(ControllerRecordProblem)
  {
    guard report.kind != .input else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.reportKind",
        "a startup write sends an output or feature report"
      )
    }
    guard Self.lengthRange.contains(report.length) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.reportLength",
        "a startup report is 2...128 bytes long"
      )
    }
    guard bytes.count == report.writableBytes.count else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.bytesCount",
        arguments: ["\(report.writableBytes.count)"],
        "a startup write lists every byte after the report ID: \(report.writableBytes.count)"
      )
    }
    guard delayMilliseconds.map({ (0...1000).contains($0) }) ?? true else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.delay",
        "a startup delay is 0...1000 ms"
      )
    }
    guard transport.map(Self.transports.contains) ?? true else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.transport",
        "a startup transport is USB, BluetoothClassic or BluetoothLE"
      )
    }
    guard crc32Seed == nil || report.length > SonyBluetoothCRC32.trailerLength else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.crcRoom",
        "a CRC startup report has room for its 4-byte trailer"
      )
    }
    self.report = report
    self.bytes = bytes
    self.delayMilliseconds = delayMilliseconds
    self.transport = transport
    self.phase = phase
    self.crc32Seed = crc32Seed
    self.condition = condition
  }

  /// Whether this write is sent over `observed`, the controller's host transport.
  func applies(to observed: PhysicalTransport?) -> Bool {
    transport.map { $0 == observed } ?? true
  }

  /// The report this write sends.
  var write: PhysicalOutputWrite {
    var reportBytes = report.reportID == 0 ? bytes : [report.reportID] + bytes
    if let crc32Seed { SonyBluetoothCRC32.writeTrailer(seed: crc32Seed, report: &reportBytes) }
    let hidReport = PhysicalHIDOutputReport(
      reportID: report.reportID,
      bytes: reportBytes,
      startupDelayMilliseconds: delayMilliseconds
    )
    return report.kind == .feature ? .hidFeature(hidReport) : .hidOutput(hidReport)
  }
}

/// One fixed raw-USB packet sent when OJD starts a raw-USB controller.
///
/// A protocol description carries the packets every controller of its family needs.
public struct USBStartupWrite: Equatable, Sendable {
  /// The packet bytes.
  public let bytes: [UInt8]
  /// The OUT endpoint; nil uses the controller's own output endpoint.
  public let endpoint: UInt8?
  /// The transfer timeout; nil uses the family's USB timeout tuning.
  public let timeoutMilliseconds: Int?
  /// The wait before this packet, replacing the startup interval; nil keeps the interval.
  public let delayMilliseconds: Int?
  /// The index of a byte the driver stamps with its per-session value: the GIP sequence number,
  /// or the Switch 2 link byte.
  public let sessionByte: Int?
  /// Whether a rejected transfer is logged and skipped instead of failing startup.
  public let toleratesRejection: Bool
  /// Which controllers the write is for.
  public let condition: StartupWriteCondition

  /// The accepted packet lengths.
  static let bytesRange = 1...64
  /// The accepted endpoint numbers.
  static let endpointRange = 1...127
  /// The accepted timeout values, in milliseconds.
  static let timeoutRange = 1...60_000

  /// Fails unless `bytes` is 1...64 long, the endpoint is 1...127, the timeout is 1...60000 ms,
  /// the delay is 0...1000 ms, and the session byte indexes `bytes`.
  init(
    bytes: [UInt8],
    endpoint: UInt8? = nil,
    timeoutMilliseconds: Int? = nil,
    delayMilliseconds: Int? = nil,
    sessionByte: Int? = nil,
    toleratesRejection: Bool = false,
    condition: StartupWriteCondition = .always
  )
    throws(ControllerRecordProblem)
  {
    guard Self.bytesRange.contains(bytes.count) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.usbLength",
        "a USB startup packet is 1...64 bytes long"
      )
    }
    guard endpoint.map({ Self.endpointRange.contains(Int($0)) }) ?? true else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.usbEndpoint",
        "a USB startup endpoint is 1...127"
      )
    }
    guard timeoutMilliseconds.map(Self.timeoutRange.contains) ?? true else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.usbTimeout",
        "a USB startup timeout is 1...60000 ms"
      )
    }
    guard delayMilliseconds.map({ (0...1000).contains($0) }) ?? true else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.delay",
        "a startup delay is 0...1000 ms"
      )
    }
    guard sessionByte.map({ (0..<bytes.count).contains($0) }) ?? true else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.startupWrite.sessionByte",
        "a USB startup session byte indexes the packet"
      )
    }
    self.bytes = bytes
    self.endpoint = endpoint
    self.timeoutMilliseconds = timeoutMilliseconds
    self.delayMilliseconds = delayMilliseconds
    self.sessionByte = sessionByte
    self.toleratesRejection = toleratesRejection
    self.condition = condition
  }

  /// This write limited by `condition` instead.
  func with(condition: StartupWriteCondition) throws(ControllerRecordProblem) -> Self {
    try Self(
      bytes: bytes,
      endpoint: endpoint,
      timeoutMilliseconds: timeoutMilliseconds,
      delayMilliseconds: delayMilliseconds,
      sessionByte: sessionByte,
      toleratesRejection: toleratesRejection,
      condition: condition
    )
  }

  /// The packet to send, on `defaultEndpoint` and with `defaultTimeoutMilliseconds` unless this
  /// write names its own. `session` gives the value of the session byte.
  func write(
    defaultEndpoint: UInt8,
    defaultTimeoutMilliseconds: Int,
    session: ((_ bytes: [UInt8]) -> UInt8)? = nil
  ) -> PhysicalOutputWrite {
    var packetBytes = bytes
    if let sessionByte, let session { packetBytes[sessionByte] = session(bytes) }
    return .usb(
      PhysicalUSBOutputPacket(
        endpoint: endpoint ?? defaultEndpoint,
        bytes: packetBytes,
        timeoutMilliseconds: UInt32(timeoutMilliseconds ?? defaultTimeoutMilliseconds),
        startupDelayMilliseconds: delayMilliseconds
      ),
      toleratesRejection: toleratesRejection
    )
  }
}
