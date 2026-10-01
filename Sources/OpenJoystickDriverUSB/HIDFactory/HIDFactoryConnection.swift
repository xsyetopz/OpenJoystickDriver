import IOKit
import OpenJoystickDriverKit
import SwifterKit

/// A host get-report request from the factory. `complete` answers it once.
struct HIDFactoryGetReport: Sendable {
  let device: UInt32
  let type: VirtualHostReportType
  let reportID: UInt32
  let capacity: Int
  let complete: @Sendable (_ bytes: [UInt8], _ status: IOReturn) async throws -> Void
}

enum HIDFactoryEvent: Sendable {
  case setReport(device: UInt32, type: VirtualHostReportType, reportID: UInt32, bytes: [UInt8])
  case getReport(HIDFactoryGetReport)
  /// The system removed the device without a request from OJD.
  case terminated(device: UInt32)
}

/// A factory command failed with this `IOReturn`.
struct HIDFactoryStatusError: Error, Equatable { let status: IOReturn }

/// One client connection to the HID device factory. Devices are named by their raw handle.
protocol HIDFactoryConnection: Sendable {
  /// The factory's events in arrival order. The sequence ends when the connection closes, and
  /// the factory then removes every device this connection created.
  var events: AsyncStream<HIDFactoryEvent> { get }
  func createDevice(_ configuration: HIDDeviceConfiguration) async throws -> UInt32
  func terminateDevice(_ device: UInt32) async throws
  func submitInputReport(_ bytes: [UInt8], to device: UInt32) async throws
}

/// The SwifterKit runtime connection to `VirtualHIDExtensionConfiguration`'s factory.
final class SwifterKitHIDFactoryConnection: HIDFactoryConnection {
  let events: AsyncStream<HIDFactoryEvent>
  private let context: DriverContext
  private let handles = Locked<[UInt32: HIDDeviceHandle]>([:])

  /// Throws `kIOReturnNotFound` when the factory extension is not running.
  static func connect(client: DriverClient) async throws -> SwifterKitHIDFactoryConnection {
    let services = try await client.services(
      matching: VirtualHIDExtensionConfiguration.hidFactory.serviceMatch
    )
    guard let service = services.first else {
      throw HIDFactoryStatusError(status: kIOReturnNotFound)
    }
    let session = try await client.open(service)
    let runtime: DriverRuntimeConnection
    do {
      runtime = try await DriverRuntimeConnection.connect(session: session, requiring: .hid)
    } catch {
      await session.close()
      throw statusError(error)
    }
    do {
      // The factory accepts commands only from the connection that receives its events.
      let sequence = try await runtime.events()
      return SwifterKitHIDFactoryConnection(
        runtime: runtime,
        context: await DriverContext(runtime: runtime),
        sequence: sequence
      )
    } catch {
      await runtime.close()
      throw statusError(error)
    }
  }

  private init(
    runtime: DriverRuntimeConnection,
    context: DriverContext,
    sequence: DriverEventSequence
  ) {
    self.context = context
    let (stream, continuation) = AsyncStream.makeStream(of: HIDFactoryEvent.self)
    events = stream
    Task { [handles] in
      do {
        for try await event in sequence {
          if let decoded = Self.decode(event, context: context, handles: handles) {
            continuation.yield(decoded)
          }
        }
      } catch {
        print("[HIDFactory] Event stream ended: \(error)")
      }
      continuation.finish()
      await runtime.close()
    }
  }

  func createDevice(_ configuration: HIDDeviceConfiguration) async throws -> UInt32 {
    do {
      let handle = try await context.createHIDDevice(configuration)
      handles.withLock { $0[handle.rawValue] = handle }
      return handle.rawValue
    } catch { throw Self.statusError(error) }
  }

  func terminateDevice(_ device: UInt32) async throws {
    guard let handle = handles.withLock({ $0.removeValue(forKey: device) }) else { return }
    do { try await context.terminateHIDDevice(handle) } catch { throw Self.statusError(error) }
  }

  func submitInputReport(_ bytes: [UInt8], to device: UInt32) async throws {
    guard let handle = handles.withLock({ $0[device] }) else {
      throw HIDFactoryStatusError(status: kIOReturnNoDevice)
    }
    do {
      try await context.submitHIDInputReport(HIDReport(bytes: bytes, type: .input), to: handle)
    } catch { throw Self.statusError(error) }
  }

  private static func decode(
    _ event: DriverEvent,
    context: DriverContext,
    handles: Locked<[UInt32: HIDDeviceHandle]>
  ) -> HIDFactoryEvent? {
    if let set = try? event.hidFactoryReport() {
      return .setReport(
        device: set.device.rawValue,
        type: reportType(set.report.type),
        reportID: set.report.options & 0xFF,
        bytes: set.report.bytes
      )
    }
    if let get = try? event.hidFactoryGetReportRequest() {
      return .getReport(
        HIDFactoryGetReport(
          device: get.device.rawValue,
          type: reportType(get.request.type),
          reportID: get.request.reportID,
          capacity: Int(get.request.capacity)
        ) { bytes, status in
          try await context.completeHIDGetReport(get, bytes: bytes, status: status)
        }
      )
    }
    if let device = try? event.hidFactoryDeviceTerminated() {
      handles.withLock { _ = $0.removeValue(forKey: device.rawValue) }
      return .terminated(device: device.rawValue)
    }
    return nil
  }

  private static func reportType(_ type: HIDReportType) -> VirtualHostReportType {
    switch type {
    case .input: .input
    case .output: .output
    case .feature: .feature
    }
  }

  private static func statusError(_ error: any Error) -> any Error {
    guard let driverKitError = error as? DriverKitError,
      case .ioReturn(let status) = driverKitError.kind
    else { return error }
    return HIDFactoryStatusError(status: status)
  }
}
