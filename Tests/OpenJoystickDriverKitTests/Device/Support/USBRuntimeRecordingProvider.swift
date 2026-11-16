import Foundation

@testable import OpenJoystickDriverKit

actor USBRuntimeRecordingProvider: USBTransportProvider {
  let session = USBRuntimeRecordingSession()
  private(set) var options: USBTransportOpenOptions?

  func devices() -> [USBTransportDevice] { [] }

  func open(
    _: USBTransportDevice,
    options: USBTransportOpenOptions
  ) -> any USBTransportSession {
    self.options = options
    return session
  }
}

struct USBWriteRecord: Equatable, Sendable {
  let endpoint: UInt8
  let data: [UInt8]
}

actor USBRuntimeRecordingSession: USBTransportSession {
  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  private(set) var writeEndpoints: [UInt8] = []
  private(set) var readEndpoints: [UInt8] = []

  func write(endpoint: UInt8, data: [UInt8], timeout _: UInt32) -> Int {
    writeEndpoints.append(endpoint)
    return data.count
  }

  func read(endpoint: UInt8, length _: Int, timeout _: UInt32) -> [UInt8] {
    readEndpoints.append(endpoint)
    return [0]
  }
}
