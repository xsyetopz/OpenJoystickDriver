/// The steps one mode runs around a controller session: vendor control transfers, startup writes, a
/// post-handshake settle, keep-alive packets, shutdown packets, and the rumble report template.
///
/// A mode names every step it runs; a step it does not name does not run.
public struct ControllerSession: Equatable, Sendable {
  /// Fixed HID reports sent when OJD starts the controller.
  public let startupWrites: [RecordStartupWrite]
  /// Fixed raw-USB packets sent when OJD starts the controller.
  public let usbStartupWrites: [USBStartupWrite]
  /// Packets repeated at an interval while a raw-USB session runs.
  let keepAlive: KeepAlive?
  /// The wait after the handshake before the first input transfer, in milliseconds.
  public let settleMilliseconds: Int?
  /// Raw-USB packets sent when the session closes.
  public let shutdownWrites: [USBStartupWrite]
  /// Vendor control transfers, run before startup in the order listed.
  public let controlTransfers: [VendorControlTransfer]
  /// The rumble report, for a driver that encodes rumble from it.
  public let rumbleTemplate: RumbleOutputTemplate?

  /// A session that runs nothing.
  public static let none = Self()

  /// Creates a session from the steps a mode runs; every step not given does not run.
  init(
    startupWrites: [RecordStartupWrite] = [],
    usbStartupWrites: [USBStartupWrite] = [],
    keepAlive: KeepAlive? = nil,
    settleMilliseconds: Int? = nil,
    shutdownWrites: [USBStartupWrite] = [],
    controlTransfers: [VendorControlTransfer] = [],
    rumbleTemplate: RumbleOutputTemplate? = nil
  ) {
    self.startupWrites = startupWrites
    self.usbStartupWrites = usbStartupWrites
    self.keepAlive = keepAlive
    self.settleMilliseconds = settleMilliseconds
    self.shutdownWrites = shutdownWrites
    self.controlTransfers = controlTransfers
    self.rumbleTemplate = rumbleTemplate
  }

  /// The accepted values of `settleMilliseconds`.
  static let settleRange = 1...60_000
}

/// A vendor control transfer on the device, gated by match keys.
public struct VendorControlTransfer: Equatable, Sendable {
  /// The device strings and release the transfer requires; a key that is nil does not constrain.
  public struct Gate: Equatable, Sendable {
    /// The manufacturer string the device must report.
    public let manufacturer: String?
    /// The product string the device must report.
    public let product: String?
    /// The `bcdDevice` release range the device must report.
    public let bcdDevice: ClosedRange<UInt16>?

    /// Whether every key present equals the device's own value.
    ///
    /// A key the device does not report does not hold.
    public func holds(manufacturer: String?, product: String?, release: UInt16?) -> Bool {
      if let expected = self.manufacturer, manufacturer != expected { return false }
      if let expected = self.product, product != expected { return false }
      if let bcdDevice {
        guard let release, bcdDevice.contains(release) else { return false }
      }
      return true
    }
  }

  /// The USB `bmRequestType`; direction, type and recipient.
  public let bmRequestType: UInt8
  /// The USB `bRequest`.
  public let bRequest: UInt8
  /// The USB `wValue`.
  public let wValue: UInt16
  /// The USB `wIndex`.
  public let wIndex: UInt16
  /// The USB `wLength`; the data length of an IN transfer.
  public let wLength: UInt16
  /// The bytes an OUT transfer writes; nil for an IN transfer and for an OUT transfer without a
  /// data stage.
  public let data: [UInt8]?
  /// The transfer timeout; nil uses the family's USB command timeout.
  public let timeoutMilliseconds: Int?
  /// The wait after this transfer; nil adds none.
  public let delayMilliseconds: Int?
  /// Whether a rejected transfer is logged and skipped instead of failing startup.
  public let toleratesRejection: Bool
  /// The device strings and release the transfer requires.
  public let match: Gate

  /// The accepted values of `timeoutMilliseconds`.
  static let timeoutRange = 1...60_000
  /// The accepted values of `delayMilliseconds`.
  static let delayRange = 0...1000
  /// The accepted values of `wLength`.
  static let lengthRange = 0...64
  /// The accepted values of `bmRequestType`: vendor requests, in either direction, to any
  /// recipient.
  static let requestTypes: Set<UInt8> = [0x40, 0x41, 0x42, 0x43, 0xC0, 0xC1, 0xC2, 0xC3]

  /// Whether the transfer reads from the device, by the direction bit of `bmRequestType`.
  var isInput: Bool { bmRequestType & 0x80 != 0 }

  /// The transfer for the USB transport.
  func request() throws -> USBControlTransferRequest {
    let stage: USBControlTransferRequest.DataStage =
      if isInput {
        .input(length: wLength)
      } else if let data {
        .output(data)
      } else {
        .none
      }
    return try USBControlTransferRequest(
      kind: .vendor,
      recipient: USBControlTransferRequest.Recipient(rawValue: bmRequestType & 0x1F) ?? .device,
      request: bRequest,
      value: wValue,
      index: wIndex,
      dataStage: stage
    )
  }
}
