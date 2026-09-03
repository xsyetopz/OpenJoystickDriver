import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct USBResolutionRuntimeTests {
  @Test func deviceManagerResolvedProfileReachesOpenStartupWriteAndFirstRead() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E)
    let resolved = DeviceTransportProfile(
      inputEndpoint: 0x84,
      outputEndpoint: 0x04,
      interfaceNumber: 2,
      alternateSetting: 1,
      needsSetConfiguration: true
    )
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 7,
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      locationID: 8
    )
    let provider = USBManagerResolutionProvider(device: device, resolvedProfile: resolved)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )

    let runtimeIdentifier = DeviceIdentifier(
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      locationID: device.locationID
    )
    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed(runtimeIdentifier)
    )
    await provider.waitForOpen()
    await provider.session.waitForFirstRead()

    #expect(await provider.options == USBTransportOpenOptions(transportProfile: resolved))
    #expect(
      await provider.session.writes == [
        USBWriteRecord(endpoint: resolved.outputEndpoint, data: [0x01, 0x03, 0x06])
      ]
    )
    #expect(await provider.session.readEndpoints == [resolved.inputEndpoint])
    await manager.stop()
  }

  @Test func resolvedProfileReachesOpenHandshakeReadAndWrite() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E)
    let resolved = DeviceTransportProfile(
      inputEndpoint: 0x84,
      outputEndpoint: 0x04,
      interfaceNumber: 2,
      alternateSetting: 1,
      needsSetConfiguration: true
    )
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 7,
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      locationID: 8
    )
    let provider = USBRuntimeRecordingProvider()
    let parser = ParserRegistry().parser(for: identifier, transportProfile: resolved)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      parser: parser,
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider,
      transportProfile: resolved
    )

    let result = await pipeline.openDeviceWithRetry(provider: provider, device: device)
    let handle = try #require(
      ifCaseOpened(result),
      "expected the configured fallback profile to reach open"
    )
    #expect(await provider.options == USBTransportOpenOptions(transportProfile: resolved))

    #expect(await pipeline.performUSBHandshake(handle: handle))
    try await pipeline.sendUSBStartupOutputPackets(handle: handle)
    _ = try await pipeline.readInterrupt(handle: handle, inEndpoint: resolved.inputEndpoint)

    let writeEndpoints = await provider.session.writeEndpoints
    let readEndpoints = await provider.session.readEndpoints
    #expect(!writeEndpoints.isEmpty)
    #expect(writeEndpoints.allSatisfy { $0 == resolved.outputEndpoint })
    #expect(readEndpoints == [resolved.inputEndpoint])
  }

  private func ifCaseOpened(_ result: DevicePipeline.USBOpenResult) -> (any USBTransportSession)? {
    guard case .opened(let handle) = result else { return nil }
    return handle
  }
}

private actor USBRuntimeRecordingProvider: USBTransportProvider {
  let session = USBRuntimeRecordingSession()
  private(set) var options: USBTransportOpenOptions?

  func devices() -> [USBTransportDevice] { [] }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions)
    -> any USBTransportSession
  {
    self.options = options
    return session
  }
}

private struct USBWriteRecord: Equatable, Sendable {
  let endpoint: UInt8
  let data: [UInt8]
}

private actor USBManagerResolutionProvider: USBTransportProvider {
  let device: USBTransportDevice
  let resolvedProfile: DeviceTransportProfile
  let session = USBManagerResolutionSession()
  private(set) var options: USBTransportOpenOptions?
  private var didOpen = false
  private var openContinuation: CheckedContinuation<Void, Never>?

  init(device: USBTransportDevice, resolvedProfile: DeviceTransportProfile) {
    self.device = device
    self.resolvedProfile = resolvedProfile
  }

  func devices() -> [USBTransportDevice] { [device] }

  func resolveTransportProfile(for device: USBTransportDevice, configured: DeviceTransportProfile)
    -> DeviceTransportProfile
  { resolvedProfile }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions)
    -> any USBTransportSession
  {
    self.options = options
    didOpen = true
    openContinuation?.resume()
    openContinuation = nil
    return session
  }

  func waitForOpen() async {
    guard !didOpen else { return }
    await withCheckedContinuation { openContinuation = $0 }
  }
}

private actor USBManagerResolutionSession: USBTransportSession {
  private(set) var writes: [USBWriteRecord] = []
  private(set) var readEndpoints: [UInt8] = []
  private var didRead = false
  private var firstReadContinuation: CheckedContinuation<Void, Never>?

  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) -> Int {
    writes.append(USBWriteRecord(endpoint: endpoint, data: data))
    return data.count
  }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    readEndpoints.append(endpoint)
    if !didRead {
      didRead = true
      firstReadContinuation?.resume()
      firstReadContinuation = nil
    }
    throw USBTransportError.disconnected
  }

  func waitForFirstRead() async {
    guard !didRead else { return }
    await withCheckedContinuation { firstReadContinuation = $0 }
  }
}

private actor USBRuntimeRecordingSession: USBTransportSession {
  private(set) var writeEndpoints: [UInt8] = []
  private(set) var readEndpoints: [UInt8] = []

  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) -> Int {
    writeEndpoints.append(endpoint)
    return data.count
  }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) -> [UInt8] {
    readEndpoints.append(endpoint)
    return [0]
  }
}
