import Foundation
import IOUSBHost
import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverUSB

struct IOUSBHostTransferTests {
  @Test
  func controlRequestBecomesIOUSBHostSetupPacket() throws {
    let request = try USBControlTransferRequest(
      kind: .vendor,
      recipient: .interface,
      request: 0x05,
      value: 0x1234,
      index: 3,
      dataStage: .input(length: 16)
    )

    let setup = IOUSBHostTransportProvider.deviceRequest(for: request)

    #expect(setup.bmRequestType == 0xC1)
    #expect(setup.bRequest == 0x05)
    #expect(setup.wValue == 0x1234)
    #expect(setup.wIndex == 3)
    #expect(setup.wLength == 16)
  }

  @Test
  func bulkPipesHonorTimeoutAndInterruptPipesUseZero() {
    #expect(
      IOUSBHostTransportProvider.pipeCompletionTimeout(
        endpointAttributes: 0x02,
        milliseconds: 2_500
      ) == 2.5
    )
    #expect(
      IOUSBHostTransportProvider.pipeCompletionTimeout(
        endpointAttributes: 0x03,
        milliseconds: 2_500
      ) == 0
    )
    #expect(
      IOUSBHostTransportProvider.pipeCompletionTimeout(endpointAttributes: 0x02, milliseconds: 0)
        == 0
    )
  }
}

struct USBDriverKitTransferTests {
  @Test
  func controlRequestMapsOntoSwifterKitSetupPacket() throws {
    let input = try USBControlTransferRequest(
      kind: .vendor,
      recipient: .interface,
      request: 0x07,
      value: 0x1234,
      index: 2,
      dataStage: .input(length: 8)
    )
    let output = try USBControlTransferRequest(
      kind: .class,
      recipient: .device,
      request: 0x09,
      dataStage: .output([1, 2, 3])
    )

    let mappedInput = USBDriverKitTransportProvider.controlRequest(for: input)
    let mappedOutput = USBDriverKitTransportProvider.controlRequest(for: output)

    #expect(
      mappedInput
        == USBControlRequest(requestType: 0xC1, request: 0x07, value: 0x1234, index: 2, length: 8)
    )
    #expect(mappedInput.direction == .in)
    #expect(mappedOutput == USBControlRequest(requestType: 0x20, request: 0x09, length: 3))
    #expect(mappedOutput.direction == .out)
    _ = try DriverCommand.usbControlTransfer(mappedInput, data: input.outputData)
    _ = try DriverCommand.usbControlTransfer(mappedOutput, data: output.outputData)
  }

  @Test
  func setConfigurationKeepsSetupPacketUsedBeforeTypedRequest() throws {
    let request = try USBControlTransferRequest(
      kind: .standard,
      recipient: .device,
      request: USBRequest.setConfiguration,
      value: 1
    )

    #expect(
      USBDriverKitTransportProvider.controlRequest(for: request)
        == USBControlRequest(
          requestType: USBRequestType.out | USBRequestType.standard | USBRequestType.device,
          request: USBRequest.setConfiguration,
          value: 1
        )
    )
  }

  @Test
  func endpointTransfersWithMismatchedDirectionOrLengthAreRejected() async {
    let session = detachedSession()

    await #expect(throws: USBTransportError.notSupported) {
      try await session.read(endpoint: 0x02, length: 64, timeout: 10)
    }
    await #expect(throws: USBTransportError.notSupported) {
      try await session.write(endpoint: 0x81, data: [1], timeout: 10)
    }
    await #expect(throws: USBTransportError.notSupported) {
      try await session.read(endpoint: 0x81, length: 0, timeout: 10)
    }
    await #expect(throws: USBTransportError.notSupported) {
      try await session.write(endpoint: 0x02, data: [], timeout: 10)
    }
  }

  @Test
  func validEndpointAndControlTransfersReachRuntime() async throws {
    let session = detachedSession()
    let control = try USBControlTransferRequest(
      kind: .vendor,
      recipient: .interface,
      request: 1,
      dataStage: .input(length: 4)
    )

    await #expect(throws: USBTransportError.disconnected) {
      try await session.read(endpoint: 0x81, length: 64, timeout: 10)
    }
    await #expect(throws: USBTransportError.disconnected) {
      try await session.write(endpoint: 0x02, data: [1, 2], timeout: 10)
    }
    await #expect(throws: USBTransportError.disconnected) {
      try await session.controlTransfer(control, timeout: 10)
    }
  }

  @Test
  func controlDataStageBeyondRuntimeLimitIsRejected() async throws {
    let session = detachedSession()
    let oversized = try USBControlTransferRequest(
      kind: .vendor,
      recipient: .device,
      request: 1,
      dataStage: .output([UInt8](repeating: 0, count: 65_481))
    )

    await #expect(throws: USBTransportError.notSupported) {
      try await session.controlTransfer(oversized, timeout: 10)
    }
  }

  @Test
  func closedSessionRejectsTransfersAndClosesRuntimeOnce() async throws {
    let closes = CloseCounter()
    let session = USBDriverKitTransportSession(context: DriverContext(capabilities: .usb)) {
      await closes.increment()
    }

    await session.close()
    await session.close()

    #expect(await closes.count == 1)
    #expect(await session.inputOwnership == .unknown)
    await #expect(throws: USBTransportError.disconnected) {
      try await session.read(endpoint: 0x81, length: 64, timeout: 10)
    }
    await #expect(throws: USBTransportError.disconnected) {
      try await session.controlTransfer(
        USBControlTransferRequest(kind: .standard, recipient: .device, request: 0),
        timeout: 10
      )
    }
  }

  private func detachedSession() -> USBDriverKitTransportSession {
    USBDriverKitTransportSession(context: DriverContext(capabilities: .usb)) {}
  }
}

private actor CloseCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}
