import Foundation

@testable import OpenJoystickDriverKit

actor USBEnumerationPollingProvider: USBTransportProvider {
  enum Reply: Sendable {
    case devices([USBTransportDevice])
    case failure(USBTransportError)
  }

  private var replies: [Reply]

  init(replies: [Reply]) { self.replies = replies }

  func devices() throws -> [USBTransportDevice] {
    guard !replies.isEmpty else { return [] }
    switch replies.removeFirst() {
    case .devices(let devices): return devices
    case .failure(let error): throw error
    }
  }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) throws -> any USBTransportSession { throw USBTransportError.notSupported }
}
