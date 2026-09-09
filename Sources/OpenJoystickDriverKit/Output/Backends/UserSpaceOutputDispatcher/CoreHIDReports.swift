import CoreHID
import Foundation

extension UserSpaceOutputDispatcher {
  @available(macOS 15, *)
  final class CoreHIDDelegate: HIDVirtualDeviceDelegate {
    let handler: UserSpaceHostReportHandler

    init(handler: UserSpaceHostReportHandler) { self.handler = handler }

    func hidVirtualDevice(
      _ device: HIDVirtualDevice,
      receivedSetReportRequestOfType type: HIDReportType,
      id: HIDReportID?,
      data: Data
    ) async throws {
      do {
        let task = try handler.setReport(
          type: Self.reportType(type),
          reportID: UInt32(id?.rawValue ?? 0),
          bytes: Array(data)
        )
        try await task.value
      } catch { throw UserSpaceHostReportHandler.coreHIDError(error) }
    }

    func hidVirtualDevice(
      _ device: HIDVirtualDevice,
      receivedGetReportRequestOfType type: HIDReportType,
      id: HIDReportID?,
      maxSize: Int
    ) throws -> Data {
      do {
        return try Data(
          handler.getReport(
            type: Self.reportType(type),
            reportID: UInt32(id?.rawValue ?? 0),
            maxSize: maxSize
          )
        )
      } catch { throw UserSpaceHostReportHandler.coreHIDError(error) }
    }

    private static func reportType(_ type: HIDReportType) throws -> VirtualHostReportType {
      switch type {
      case .input: .input
      case .output: .output
      case .feature: .feature
      @unknown default: throw VirtualHostReportError.unsupported
      }
    }
  }
}
