import Dispatch
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

/// Keeps the protocol driver of a record probe on one actor, so the startup writes and the input
/// monitor share the driver's state.
private actor ControllerRecordProbeIsolation {
  /// The protocol driver that the record selects.
  private let driver: any PhysicalProtocolDriver
  /// Produced once, so the RECORD line shows the exact writes sent, sequence numbers included.
  private lazy var startupWrites = driver.startupWrites()

  /// Creates the isolation around `driver`.
  init(driver: sending any PhysicalProtocolDriver) { self.driver = driver }

  /// Prints the RECORD line of `plan` with the startup writes of the driver.
  func printRecord(plan: ControllerRecordProbePlan, transport: DeviceTransportProfile) {
    renderProbeRecord(plan: plan, startup: startupWrites, transport: transport)
  }

  /// Sends the startup writes of the driver over `session`.
  func sendStartupPackets(session: any USBTransportSession) async throws {
    try await writeProbeStartupPackets(startupWrites, session: session)
  }

  /// Reads input packets from `session` for `seconds` and parses them with the driver.
  ///
  /// - Returns: The number of packets, events and parse errors.
  func monitor(
    transport: DeviceTransportProfile,
    session: any USBTransportSession,
    seconds: Int
  ) async throws -> (packets: Int, events: Int, parseErrors: Int) {
    try await monitorProbeInput(
      driver: driver,
      transport: transport,
      session: session,
      seconds: seconds,
      isolation: self
    )
  }
}

/// Runs the record probe and exits with 0 on success, 2 when no raw USB device matches the record,
/// and another code on a failure.
///
/// With `validateOnly`, it checks the record with an unobserved driver and opens no hardware.
/// Otherwise it opens the matching raw USB device, sends the startup writes of the record and
/// monitors the input for `seconds`.
///
/// - Parameters:
///   - recordPath: The controller record file.
///   - seconds: How long to monitor the input.
///   - validateOnly: Whether to stop after validating the record.
func runControllerRecordProbe(recordPath: String, seconds: Int, validateOnly: Bool) -> Never {
  let exitCode = Locked<Int32>(0)
  let done = DispatchSemaphore(value: 0)

  Task {
    defer { done.signal() }
    do {
      let url = URL(fileURLWithPath: recordPath)
      let code =
        validateOnly
        ? try await validateProbeRecord(at: url)
        : try await probeRecordedDevice(from: url, seconds: seconds)
      exitCode.withLock { $0 = code }
    } catch {
      unsafe fputs("ERROR: record probe failed: \(error.localizedDescription)\n", unsafe stderr)
      exitCode.withLock { $0 = 1 }
    }
  }

  done.wait()
  exit(exitCode.withLock { $0 })
}

/// Validates the record at `url` with an unobserved driver and prints its RECORD line when the
/// probe drives its protocol.
///
/// - Returns: The exit code, 0.
private func validateProbeRecord(at url: URL) async throws -> Int32 {
  let protocolID = try ControllerRecordProbePlan.validate(data: Data(contentsOf: url))
  // Only a protocol the probe drives has a plan to render.
  if ControllerRecordProbePlan.probeableProtocols.contains(protocolID) {
    let plan = try ControllerRecordProbePlan(contentsOf: url)
    await ControllerRecordProbeIsolation(driver: plan.makeUnobservedDriver()).printRecord(
      plan: plan,
      transport: plan.transportProfile
    )
  }
  print("RECORD_VALIDATION result=valid")
  return 0
}

/// Opens the raw USB device that matches the record at `url`, starts it and monitors its input.
///
/// - Returns: The exit code: 0 with input packets, 3 without, 2 when no device matches, and 4 when
///   the device is refused.
private func probeRecordedDevice(from url: URL, seconds: Int) async throws -> Int32 {
  let plan = try ControllerRecordProbePlan(contentsOf: url)

  let provider = OpenJoystickDriverUSBTransportProvider()
  let devices = try await provider.devices().filter {
    $0.vendorID == plan.vendorID && $0.productID == plan.productID
  }
  print("USB_MATCHES count=\(devices.count)")
  guard let device = devices.first else {
    unsafe fputs("ERROR: no raw USB transport matches the record VID/PID\n", stderr)
    return 2
  }

  print("USB_DEVICE service=\(device.serviceID) location=\(device.locationID)")
  if let product = device.productName { print("USB_STRING product=\(product)") }
  guard let claimed = await claimProbeInterface(provider, device: device, plan: plan),
    let isolation = makeProbeIsolation(plan: plan, device: device, claimed: claimed)
  else { return 4 }
  let transport = claimed.profile
  await isolation.printRecord(plan: plan, transport: transport)
  let session = try await provider.open(
    device,
    options: USBTransportOpenOptions(transportProfile: transport)
  )
  printProbeOpen(transport: transport, device: device)

  try await isolation.sendStartupPackets(session: session)
  print("RECORD_HANDSHAKE driver=\(plan.protocolBinding.rawValue) result=complete")

  if transport.postHandshakeSettleNanoseconds > 0 {
    try await Task.sleep(nanoseconds: transport.postHandshakeSettleNanoseconds)
  }
  let summary = try await isolation.monitor(
    transport: transport,
    session: session,
    seconds: seconds
  )
  await session.close()
  print(
    "RECORD_SUMMARY packets=\(summary.packets)"
      + " events=\(summary.events) parse_errors=\(summary.parseErrors)"
  )
  return summary.packets > 0 ? 0 : 3
}

/// Validates the claimed interface of `device` as discovery does, before open can set the
/// configuration.
///
/// - Returns: The resolution, or nil after printing the refusal when the configuration cannot be
///   read or belongs to another service.
private func claimProbeInterface(
  _ provider: OpenJoystickDriverUSBTransportProvider,
  device: USBTransportDevice,
  plan: ControllerRecordProbePlan
) async -> USBTransportResolution? {
  let passive = await provider.resolveTransport(for: device, configured: plan.transportProfile)
  let claimed: USBTransportResolution
  do {
    claimed = try await provider.resolveUSBConfiguration(device, passive: passive)
  } catch USBConfigurationReadFailure.refused {
    let owner = try? await provider.exclusiveOwner(of: device)
    refuseProbeDevice(
      reason: owner == nil ? "configuration-unreadable" : "device-in-use",
      message: owner.map {
        "the host refused the USB configuration read because \($0) holds the device; "
          + "close that program or reconnect the controller"
      } ?? "the host refused the USB configuration read and reports no exclusive owner; "
        + "reconnect the controller"
    )
    return nil
  } catch {
    refuseProbeDevice(
      reason: "configuration-unreadable",
      message: "the device's USB configuration descriptor could not be read (\(error)); "
        + "try again"
    )
    return nil
  }
  guard claimed.physicalDevice.map({ $0.serviceAddress == device.serviceAddress }) ?? true
  else {
    refuseProbeDevice(
      reason: "configuration-unobserved",
      message: "the USB configuration that was read belongs to another service; try again"
    )
    return nil
  }
  return claimed
}

/// Builds the driver that the record selects for the claimed interface, on its own isolation.
///
/// - Returns: The isolation, or nil after printing the refusal when the interface violates the
///   record's contract.
private func makeProbeIsolation(
  plan: ControllerRecordProbePlan,
  device: USBTransportDevice,
  claimed: USBTransportResolution
) -> ControllerRecordProbeIsolation? {
  switch plan.makeDriver(for: device, claimed: claimed) {
  case .success(let validated): return ControllerRecordProbeIsolation(driver: validated)
  case .failure(let reason):
    refuseProbeDevice(
      reason: reason.rawValue,
      message: "the device does not satisfy the record's interface contract"
    )
    return nil
  }
}

/// Prints the USB_CONFIGURATION, USB_ALTERNATE_SETTING and USB_OPEN lines of an opened device.
private func printProbeOpen(transport: DeviceTransportProfile, device: USBTransportDevice) {
  if transport.needsSetConfiguration { print("USB_CONFIGURATION value=1 result=set") }
  if transport.alternateSetting != 0 {
    print(
      "USB_ALTERNATE_SETTING interface=\(transport.interfaceNumber)"
        + " value=\(transport.alternateSetting) result=set"
    )
  }
  print(
    "USB_OPEN interface=\(transport.interfaceNumber)"
      + " route=\(device.route.rawValue) result=opened"
  )
}

/// Reports a device refused before any write, when its claimed interface cannot be validated.
private func refuseProbeDevice(reason: String, message: String) {
  print("RECORD_BINDING result=refused reason=\(reason)")
  unsafe fputs("ERROR: \(message) (\(reason))\n", unsafe stderr)
}

/// Prints the RECORD line: the identity, the USB transport profile and the startup packets of
/// `plan`.
private func renderProbeRecord(
  plan: ControllerRecordProbePlan,
  startup: [PhysicalOutputWrite],
  transport: DeviceTransportProfile
) {
  let profileStartup = plan.startupPackets.joined(separator: ",")
  let usbStartupBytes = startup.map(\.hexBytes).joined(separator: ",")
  print(
    "RECORD identity=\"\(plan.name)\" vid=\(plan.vendorID) pid=\(plan.productID)"
      + " driver=\(plan.protocolBinding.rawValue)" + " interface=\(transport.interfaceNumber)"
      + " in=\(hex(transport.inputEndpoint))" + " out=\(hex(transport.outputEndpoint))"
      + " configuration=\(transport.needsSetConfiguration ? "set1" : "current")"
      + " profile_startup=\(profileStartup.isEmpty ? "none" : profileStartup)"
      + " usb_startup=\(usbStartupBytes.isEmpty ? "none" : usbStartupBytes)"
  )
}

/// Writes each of `startup` to `session` and prints a USB_TX line for it.
///
/// A write that the transport reports as an ignorable startup output error is printed as ignored.
///
/// - Throws: ``USBTransportError`` for any other write failure.
private func writeProbeStartupPackets(
  _ startup: [PhysicalOutputWrite],
  session: any USBTransportSession
) async throws {
  for write in startup {
    do { try await writeProbe(write, session: session) } catch let error as USBTransportError
      where isIgnorableUSBStartupOutputError(write, error: error)
    {
      print(
        "USB_TX endpoint=\(write.probeEndpoint) result=ignored"
          + " detail=\"\(error)\" bytes=\(write.hexBytes)"
      )
    }
  }
}

/// Sends a USB write through `session`.
///
/// - Throws: ``USBTransportError/notSupported`` for a HID write, and any error of the session.
private func sendUSBWrite(
  _ write: PhysicalOutputWrite,
  session: any USBTransportSession
)
  async throws
{
  switch write {
  case .usb(let packet, _):
    _ = try await session.write(
      endpoint: packet.endpoint,
      data: packet.bytes,
      timeout: packet.timeoutMilliseconds
    )
  case .hidOutput, .hidFeature: throw USBTransportError.notSupported
  }
}

/// Writes one driver-produced write and prints it as a USB_TX line.
private func writeProbe(_ write: PhysicalOutputWrite, session: any USBTransportSession) async throws
{
  try await sendUSBWrite(write, session: session)
  print("USB_TX endpoint=\(write.probeEndpoint) bytes=\(write.hexBytes)")
}

/// Reads input packets for `seconds`, prints each event and parse error, and sends the keep-alive
/// and lifecycle packets that the driver asks for.
///
/// - Returns: The number of packets, events and parse errors.
private func monitorProbeInput(
  driver: any PhysicalProtocolDriver,
  transport: DeviceTransportProfile,
  session: any USBTransportSession,
  seconds: Int,
  isolation: isolated ControllerRecordProbeIsolation
) async throws -> (packets: Int, events: Int, parseErrors: Int) {
  let deadline = Date().addingTimeInterval(TimeInterval(seconds))
  let keepAliveInterval = driver.sessionPlan.usbKeepAliveIntervalNanoseconds
  var lastKeepAlive = DispatchTime.now().uptimeNanoseconds
  var packetCount = 0
  var eventCount = 0
  var parseErrorCount = 0

  while Date() < deadline {
    let now = DispatchTime.now().uptimeNanoseconds
    if let keepAliveInterval, now &- lastKeepAlive >= keepAliveInterval {
      lastKeepAlive = now
      do {
        for write in driver.keepAliveWrites() {
          try await sendUSBWrite(write, session: session)
          print("USB_KEEPALIVE result=sent")
        }
      } catch { print("USB_KEEPALIVE result=error detail=\(error.localizedDescription)") }
    }

    do {
      let bytes = try await session.read(
        endpoint: transport.inputEndpoint,
        length: 64,
        timeout: 250
      )
      packetCount += 1
      print(
        "USB_RX endpoint=\(hex(transport.inputEndpoint))"
          + " len=\(bytes.count) bytes=\(bytes.hexBytes)"
      )
      do {
        let event = try driver.parse(
          report: Data(bytes),
          receivedAt: MonotonicTimestamp(nanoseconds: DispatchTime.now().uptimeNanoseconds)
        )
        for write in driver.drainPendingWrites() { try await writeProbe(write, session: session) }
        try await sendLifecyclePackets(driver: driver, session: session, isolation: isolation)
        if let event {
          eventCount += 1
          print("EVENT \(String(describing: event.state))")
        }
      } catch {
        parseErrorCount += 1
        print("PARSE_ERROR detail=\(error.localizedDescription)")
      }
      unsafe fflush(stdout)
    } catch USBTransportError.timeout { continue }
  }
  return (packetCount, eventCount, parseErrorCount)
}

/// Sends the writes that follow a connection state change that the driver reports.
private func sendLifecyclePackets(
  driver: any PhysicalProtocolDriver,
  session: any USBTransportSession,
  isolation _: isolated ControllerRecordProbeIsolation
) async throws {
  guard let state = driver.consumeInputConnectionStateChange() else { return }
  print("CONTROLLER_CONNECTION state=\(String(describing: state))")
  for write in driver.inputConnectionWrites(for: state) {
    try await writeProbe(write, session: session)
  }
}

/// Returns `value` as `0x`-prefixed lowercase hex.
private func hex<T: BinaryInteger>(_ value: T) -> String { "0x" + String(value, radix: 16) }

extension [UInt8] {
  /// The bytes as lowercase hex pairs separated by spaces.
  var hexBytes: String { map { unsafe String(format: "%02x", $0) }.joined(separator: " ") }
}

extension PhysicalOutputWrite {
  /// The endpoint of a USB write, or the report ID of a HID write, as hex.
  var probeEndpoint: String {
    switch self {
    case .usb(let packet, _): hex(packet.endpoint)
    case .hidOutput(let report), .hidFeature(let report): "report=\(hex(report.reportID))"
    }
  }

  /// The bytes of the write as lowercase hex pairs separated by spaces.
  var hexBytes: String {
    switch self {
    case .usb(let packet, _): packet.bytes.hexBytes
    case .hidOutput(let report), .hidFeature(let report): report.bytes.hexBytes
    }
  }
}
