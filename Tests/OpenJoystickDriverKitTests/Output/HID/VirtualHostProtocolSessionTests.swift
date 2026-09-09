import CoreHID
import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

func virtualHostOutput(_ bytes: [UInt8]) throws -> VirtualHostReportRequest {
  let identifier = try #require(bytes.first)
  return try VirtualHostReportRequest(
    type: .output,
    reportID: UInt32(identifier),
    bytes: bytes,
    framing: .completeReport
  )
}

struct VirtualHostProtocolSessionTests {
  @Test
  func framingNeverInfersAnInlineIDFromPayloadContent() throws {
    let payload = try VirtualHostReportRequest(
      type: .output,
      reportID: 5,
      bytes: [5, 9],
      framing: .payload
    )
    #expect(payload.payload == [5, 9])
    #expect(payload.completeReport == [5, 5, 9])
    let complete = try VirtualHostReportRequest(
      type: .output,
      reportID: 5,
      bytes: [5, 5, 9],
      framing: .completeReport
    )
    #expect(complete.payload == payload.payload)
    #expect(throws: VirtualHostReportError.malformed) {
      try VirtualHostReportRequest(type: .output, reportID: 5, bytes: [9], framing: .completeReport)
    }
    #expect(throws: VirtualHostReportError.malformed) {
      try VirtualHostReportRequest(type: .output, reportID: 256, bytes: [], framing: .payload)
    }
  }

  @Test
  func getReportChecksTypeIdentityCapacityAndLifetime() throws {
    let format = OJDGenericGamepadFormat()
    let session = VirtualHostProtocolSession(format: format)
    let current = format.buildInputReport(from: VirtualGamepadState(buttons: 1))
    #expect(
      try session.getReport(type: .input, reportID: 0, maxSize: 3, currentInput: current)
        == Array(current.prefix(3))
    )
    for type in [VirtualHostReportType.feature, .output] {
      #expect(throws: VirtualHostReportError.unsupported) {
        try session.getReport(type: type, reportID: 0, maxSize: 64, currentInput: current)
      }
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try session.getReport(type: .input, reportID: 1, maxSize: 64, currentInput: current)
    }
    for size in [-1, 0] {
      #expect(throws: VirtualHostReportError.malformed) {
        try session.getReport(type: .input, reportID: 0, maxSize: size, currentInput: current)
      }
    }
    session.close()
    #expect(throws: VirtualHostReportError.closed) {
      try session.getReport(type: .input, reportID: 0, maxSize: 64, currentInput: current)
    }
  }

  @Test
  func xboxRumbleAcceptsNativeUnnumberedFraming() throws {
    let session = VirtualHostProtocolSession(format: Xbox360MacHIDReportFormat())
    let request = try VirtualHostReportRequest(
      type: .output,
      reportID: 0,
      bytes: [8, 0, 127, 255, 0, 0, 0],
      framing: .completeReport
    )
    #expect(try session.setReport(request).rumble == VirtualRumbleCommand(left: 127, right: 255))
    let malformed = try VirtualHostReportRequest(
      type: .output,
      reportID: 0,
      bytes: [8, 0, 127],
      framing: .completeReport
    )
    #expect(throws: VirtualHostReportError.malformed) { try session.setReport(malformed) }
  }

  @Test
  func nativeErrorsPreserveFailureClassification() {
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.unsupported)
        == kIOReturnUnsupported
    )
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.malformed)
        == kIOReturnBadArgument
    )
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.tooLarge)
        == kIOReturnMessageTooLarge
    )
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.closed) == kIOReturnNotOpen
    )
    if #available(macOS 15, *) {
      #expect(
        UserSpaceHostReportHandler.coreHIDError(VirtualHostReportError.unsupported) == .unsupported
      )
      #expect(
        UserSpaceHostReportHandler.coreHIDError(VirtualHostReportError.malformed) == .badArgument
      )
      #expect(
        UserSpaceHostReportHandler.coreHIDError(VirtualHostReportError.tooLarge) == .messageTooLarge
      )
      #expect(UserSpaceHostReportHandler.coreHIDError(VirtualHostReportError.closed) == .notReady)
      #expect(UserSpaceHostReportHandler.coreHIDError(CancellationError()) == .aborted)
    }
  }
}
