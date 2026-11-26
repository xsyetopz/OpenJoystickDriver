/// An open USB session to one controller interface, which a protocol driver reads and writes
/// through.
///
/// Protocol drivers depend on this port instead of a USB library or a DriverKit client. Concrete
/// transports own device discovery, interface claims, pipe lifetimes and platform error
/// translation.
public protocol USBTransportSession: AnyObject, Sendable {
  /// The input ownership that this live session confirmed, not the one discovery inferred.
  var inputOwnership: HIDInputOwnership { get async }

  /// Sends one transfer to a bulk or interrupt OUT endpoint and returns the byte count sent.
  ///
  /// - Parameters:
  ///   - endpoint: The OUT endpoint address.
  ///   - data: The bytes to send.
  ///   - timeout: The time to wait, in milliseconds.
  /// - Returns: The number of bytes sent.
  /// - Throws: ``USBTransportError/notSupported`` when `endpoint` has the IN bit set.
  @discardableResult
  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int

  /// Receives one transfer of at most `length` bytes from a bulk or interrupt IN endpoint.
  ///
  /// - Parameters:
  ///   - endpoint: The IN endpoint address.
  ///   - length: The most bytes to receive.
  ///   - timeout: The time to wait, in milliseconds, or 0 to wait with no deadline.
  /// - Throws: ``USBTransportError/notSupported`` when `endpoint` lacks the IN bit or `length`
  ///   is not positive.
  /// - Returns: The bytes received, at most `length`.
  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8]

  /// Performs one request on the default control endpoint and returns the IN data stage.
  ///
  /// OUT and no-data requests return an empty array.
  ///
  /// - Parameters:
  ///   - request: The setup packet and data stage.
  ///   - timeout: The time to wait, in milliseconds.
  /// - Returns: The IN data stage, or an empty array for an OUT or no-data request.
  /// - Throws: A ``USBTransportError`` when the transfer fails.
  @discardableResult
  func controlTransfer(
    _ request: USBControlTransferRequest,
    timeout: UInt32
  ) async throws -> [UInt8]

  /// Clears the halt state of a bulk or interrupt endpoint on the device and on the host, which
  /// returns the data toggle of both sides to `DATA0`.
  ///
  /// Every transfer pending on the endpoint ends.
  ///
  /// - Parameters:
  ///   - endpoint: The endpoint address, with the IN bit for an IN endpoint.
  ///   - timeout: The time to wait for the device's `CLEAR_FEATURE` reply, in milliseconds.
  /// - Throws: ``USBTransportError/notSupported`` when the session cannot reset the host side.
  func resynchronizeEndpoint(_ endpoint: UInt8, timeout: UInt32) async throws

  /// Closes this session; closing again has no effect.
  func close() async
}

extension USBTransportSession {
  /// Reports unknown input ownership, for a session that does not observe it.
  public var inputOwnership: HIDInputOwnership { .unknown }
  /// Yields once, for a session that holds no resource to release.
  public func close() async { await Task.yield() }

  /// Resets no endpoint: a CLEAR_FEATURE alone would leave the host's toggle where it was.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func resynchronizeEndpoint(_: UInt8, timeout _: UInt32) async throws {
    await Task.yield()
    throw USBTransportError.notSupported
  }
}

extension USBEndpointDirection {
  /// Decodes the direction bit of a USB endpoint address.
  public init(endpointAddress: UInt8) { self = endpointAddress & 0x80 == 0 ? .out : .in }
}

/// One setup packet and data stage for the default control endpoint.
///
/// The data-stage direction derives from `dataStage`, so a request cannot declare one direction
/// and carry data for the other.
public struct USBControlTransferRequest: Equatable, Sendable {
  /// The request type bits of `bmRequestType`.
  public enum RequestKind: UInt8, Equatable, Sendable {
    /// A request that the USB specification defines.
    case standard = 0x00
    /// A request that a device class defines.
    case `class` = 0x20
    /// A request that the vendor defines.
    case vendor = 0x40
  }

  /// The recipient bits of `bmRequestType`.
  public enum Recipient: UInt8, Equatable, Sendable {
    /// The device.
    case device = 0x00
    /// An interface of the device.
    case interface = 0x01
    /// An endpoint of the device.
    case endpoint = 0x02
    /// Another recipient.
    case other = 0x03
  }

  /// The data stage of a control request.
  public enum DataStage: Equatable, Sendable {
    /// No data stage.
    case none
    /// Host-to-device bytes; the count becomes `wLength`.
    case output([UInt8])
    /// Device-to-host transfer of at most `length` bytes.
    case input(length: UInt16)
  }

  /// The request type bits of `bmRequestType`.
  public let kind: RequestKind
  /// The recipient bits of `bmRequestType`.
  public let recipient: Recipient
  /// The request code (`bRequest`).
  public let request: UInt8
  /// The request value (`wValue`).
  public let value: UInt16
  /// The request index (`wIndex`).
  public let index: UInt16
  /// The data stage of the request.
  public let dataStage: DataStage

  /// Creates a control transfer request.
  ///
  /// - Throws: ``USBTransportError/notSupported`` for OUT data that is empty or longer than
  ///   `UInt16.max`, and for an IN data stage of zero bytes.
  public init(
    kind: RequestKind,
    recipient: Recipient,
    request: UInt8,
    value: UInt16 = 0,
    index: UInt16 = 0,
    dataStage: DataStage = .none
  ) throws {
    switch dataStage {
    case .none: break
    case .output(let data):
      guard !data.isEmpty, data.count <= Int(UInt16.max) else {
        throw USBTransportError.notSupported
      }
    case .input(let length): guard length > 0 else { throw USBTransportError.notSupported }
    }
    self.kind = kind
    self.recipient = recipient
    self.request = request
    self.value = value
    self.index = index
    self.dataStage = dataStage
  }

  /// The direction of the data stage; a request with no data stage counts as OUT.
  public var direction: USBEndpointDirection {
    if case .input = dataStage { return .in }
    return .out
  }

  /// `bmRequestType`: direction, kind and recipient bits.
  public var requestType: UInt8 {
    (direction == .in ? 0x80 : 0x00) | kind.rawValue | recipient.rawValue
  }

  /// The length of the data stage (`wLength`).
  public var length: UInt16 {
    switch dataStage {
    case .none: 0
    case .output(let data): UInt16(data.count)
    case .input(let length): length
    }
  }

  /// Host-to-device data-stage bytes, empty for IN and no-data requests.
  public var outputData: [UInt8] {
    guard case .output(let data) = dataStage else { return [] }
    return data
  }
}
