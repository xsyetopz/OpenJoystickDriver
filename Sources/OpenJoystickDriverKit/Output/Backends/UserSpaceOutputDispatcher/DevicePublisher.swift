import IOKit

/// The identity and report descriptor of one virtual gamepad. `IOHIDUserDevice` and every
/// ``VirtualHIDDevicePublisher`` publish the same values.
public struct VirtualHIDDeviceDescription: Sendable, Equatable {
  public let reportDescriptor: [UInt8]
  public let vendorID: UInt16
  public let productID: UInt16
  public let versionNumber: Int
  public let manufacturer: String
  public let product: String
  public let serialNumber: String
  /// The IOHID `Transport` value, such as `Bluetooth` or `USB`.
  public let transport: String
  public let locationID: UInt32
  public let primaryUsagePage: UInt32
  public let primaryUsage: UInt32

  package init(
    reportDescriptor: [UInt8],
    vendorID: UInt16,
    productID: UInt16,
    versionNumber: Int,
    manufacturer: String,
    product: String,
    serialNumber: String,
    transport: String,
    locationID: UInt32,
    primaryUsagePage: UInt32,
    primaryUsage: UInt32
  ) {
    self.reportDescriptor = reportDescriptor
    self.vendorID = vendorID
    self.productID = productID
    self.versionNumber = versionNumber
    self.manufacturer = manufacturer
    self.product = product
    self.serialNumber = serialNumber
    self.transport = transport
    self.locationID = locationID
    self.primaryUsagePage = primaryUsagePage
    self.primaryUsage = primaryUsage
  }
}

/// Answers the host's set-report and get-report requests for one published device.
///
/// Numbered reports include their ID as byte zero, as in the `IOHIDUserDevice` callbacks.
public struct VirtualHIDHostReports: Sendable {
  public typealias SetReport = @Sendable (VirtualHostReportType, UInt32, [UInt8]) -> IOReturn
  public typealias GetReport =
    @Sendable (VirtualHostReportType, UInt32, Int) -> (bytes: [UInt8], status: IOReturn)

  private let set: SetReport
  private let get: GetReport

  package init(setReport: @escaping SetReport, getReport: @escaping GetReport) {
    set = setReport
    get = getReport
  }

  init(handler: UserSpaceHostReportHandler) {
    self.init(
      setReport: { type, reportID, bytes in
        do {
          _ = try handler.setReport(type: type, reportID: reportID, bytes: bytes)
          return kIOReturnSuccess
        } catch { return UserSpaceHostReportHandler.ioKitError(error) }
      },
      getReport: { type, reportID, maxSize in
        do {
          let bytes = try handler.getReport(type: type, reportID: reportID, maxSize: maxSize)
          return (bytes, kIOReturnSuccess)
        } catch { return ([], UserSpaceHostReportHandler.ioKitError(error)) }
      }
    )
  }

  /// Applies a report the host set and returns its `IOReturn` status.
  public func setReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> IOReturn { set(type, reportID, bytes) }

  /// Returns the report the host requested, or no bytes with a failure status.
  public func getReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    maxSize: Int
  ) -> (bytes: [UInt8], status: IOReturn) { get(type, reportID, maxSize) }
}

/// Publishes virtual gamepads through a provider other than `IOHIDUserDevice`, such as OJD's
/// DriverKit HID device factory.
public protocol VirtualHIDDevicePublisher: Sendable {
  /// Publishes one device, or returns nil so the dispatcher falls back to `IOHIDUserDevice`.
  ///
  /// The publisher calls `onLost` at most once, when the returned device stopped publishing and
  /// will not come back on its own; the dispatcher then replaces it with its current state.
  func publish(
    _ device: VirtualHIDDeviceDescription,
    hostReports: VirtualHIDHostReports,
    onLost: @escaping @Sendable () -> Void
  ) async -> (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?
}
