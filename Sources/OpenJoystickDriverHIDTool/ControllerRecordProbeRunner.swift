import Dispatch
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

private let controllerRecordProbeKeepAliveIntervalNanoseconds: UInt64 = 4_000_000_000

func runControllerRecordProbe(recordPath: String, seconds: Int, validateOnly: Bool) -> Never {
  let exitCode = ExitCodeBox()
  let done = DispatchSemaphore(value: 0)

  Task {
    defer { done.signal() }
    do {
      let plan = try ControllerRecordProbePlan(contentsOf: URL(fileURLWithPath: recordPath))
      let parser = plan.makeParser()
      printRecord(plan: plan, parser: parser)
      if validateOnly {
        print("RECORD_VALIDATION result=valid")
        return
      }

      let provider = OpenJoystickDriverUSBTransportProvider()
      let devices = try await provider.devices().filter {
        $0.vendorID == plan.vendorID && $0.productID == plan.productID
      }
      print("USB_MATCHES count=\(devices.count)")
      guard let device = devices.first else {
        fputs("ERROR: no raw USB transport matches the record VID/PID\n", stderr)
        exitCode.value = 2
        return
      }

      print("USB_DEVICE service=\(device.serviceID) location=\(device.locationID)")
      if let product = device.productName { print("USB_STRING product=\(product)") }
      let session = try await provider.open(
        device,
        options: USBTransportOpenOptions(transportProfile: plan.transportProfile)
      )

      if plan.transportProfile.needsSetConfiguration {
        print("USB_CONFIGURATION value=1 result=set")
      }
      let transport = plan.transportProfile
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

      try await parser.performHandshake(handle: session)
      print("RECORD_HANDSHAKE driver=\(plan.driver.rawValue) result=complete")
      try await sendStartupPackets(
        parser: parser,
        session: session,
        endpoint: transport.outputEndpoint
      )

      if transport.postHandshakeSettleNanoseconds > 0 {
        try await Task.sleep(nanoseconds: transport.postHandshakeSettleNanoseconds)
      }
      let summary = try await monitor(
        parser: parser,
        plan: plan,
        session: session,
        seconds: seconds
      )
      await session.close()
      print(
        "RECORD_SUMMARY packets=\(summary.packets)"
          + " events=\(summary.events) parse_errors=\(summary.parseErrors)"
      )
      exitCode.value = summary.packets > 0 ? 0 : 3
    } catch {
      fputs("ERROR: record probe failed: \(error.localizedDescription)\n", stderr)
      exitCode.value = 1
    }
  }

  done.wait()
  exit(exitCode.value)
}

private func printRecord(plan: ControllerRecordProbePlan, parser: any InputParser) {
  let profileStartup = plan.startupPackets.map(\.rawValue).joined(separator: ",")
  let usbStartup = (parser as? any USBStartupOutputProvider)?.usbStartupOutputPackets() ?? []
  let usbStartupBytes = usbStartup.map(\.hexBytes).joined(separator: ",")
  print(
    "RECORD identity=\"\(plan.name)\" vid=\(plan.vendorID) pid=\(plan.productID)"
      + " driver=\(plan.driver.rawValue) interface=\(plan.interfaceNumber)"
      + " in=\(hex(plan.transportProfile.inputEndpoint))"
      + " out=\(hex(plan.transportProfile.outputEndpoint))"
      + " configuration=\(plan.transportProfile.needsSetConfiguration ? "set1" : "current")"
      + " profile_startup=\(profileStartup.isEmpty ? "none" : profileStartup)"
      + " usb_startup=\(usbStartupBytes.isEmpty ? "none" : usbStartupBytes)"
  )
}

private func sendStartupPackets(
  parser: any InputParser,
  session: any USBTransportSession,
  endpoint: UInt8
) async throws {
  guard let startupOutput = parser as? any USBStartupOutputProvider else { return }
  for packet in startupOutput.usbStartupOutputPackets() {
    do {
      _ = try await session.writeInterruptPacket(endpoint: endpoint, data: packet, timeout: 2_000)
      print("USB_TX endpoint=\(hex(endpoint)) bytes=\(packet.hexBytes)")
    } catch let error as USBTransportError
      where isIgnorableUSBStartupOutputError(parser: parser, packet: packet, error: error)
    {
      print(
        "USB_TX endpoint=\(hex(endpoint)) result=ignored"
          + " detail=\"\(error)\" bytes=\(packet.hexBytes)"
      )
    }
  }
}

private func monitor(
  parser: any InputParser,
  plan: ControllerRecordProbePlan,
  session: any USBTransportSession,
  seconds: Int
) async throws -> (packets: Int, events: Int, parseErrors: Int) {
  let deadline = Date().addingTimeInterval(TimeInterval(seconds))
  var lastKeepAlive = DispatchTime.now().uptimeNanoseconds
  var packetCount = 0
  var eventCount = 0
  var parseErrorCount = 0

  while Date() < deadline {
    let now = DispatchTime.now().uptimeNanoseconds
    if now &- lastKeepAlive >= controllerRecordProbeKeepAliveIntervalNanoseconds {
      lastKeepAlive = now
      if plan.driver == .gip, plan.keepAlivePolicy == .disabled {
        print("USB_KEEPALIVE result=disabled")
      } else {
        do {
          try await parser.keepAlive(handle: session)
          print("USB_KEEPALIVE result=sent")
        } catch { print("USB_KEEPALIVE result=error detail=\(error.localizedDescription)") }
      }
    }

    do {
      let bytes = try await session.readInterruptPacket(
        endpoint: plan.transportProfile.inputEndpoint,
        length: 64,
        timeout: 250
      )
      packetCount += 1
      print(
        "USB_RX endpoint=\(hex(plan.transportProfile.inputEndpoint))"
          + " len=\(bytes.count) bytes=\(bytes.hexBytes)"
      )
      do {
        let events = try parser.parse(data: Data(bytes))
        try await sendLifecyclePackets(parser: parser, session: session, plan: plan)
        eventCount += events.count
        for event in events { print("EVENT \(String(describing: event))") }
      } catch {
        parseErrorCount += 1
        print("PARSE_ERROR detail=\(error.localizedDescription)")
      }
      fflush(stdout)
    } catch USBTransportError.timeout { continue }
  }
  return (packetCount, eventCount, parseErrorCount)
}

private func sendLifecyclePackets(
  parser: any InputParser,
  session: any USBTransportSession,
  plan: ControllerRecordProbePlan
) async throws {
  guard let lifecycle = parser as? any ControllerInputConnectionLifecycle,
    let state = lifecycle.consumeInputConnectionStateChange()
  else { return }
  print("CONTROLLER_CONNECTION state=\(String(describing: state))")
  guard let output = parser as? any USBInputConnectionOutputProvider else { return }
  for packet in output.usbInputConnectionOutputPackets(for: state) {
    _ = try await session.writeInterruptPacket(
      endpoint: plan.transportProfile.outputEndpoint,
      data: packet,
      timeout: 2_000
    )
    print("USB_TX endpoint=\(hex(plan.transportProfile.outputEndpoint)) bytes=\(packet.hexBytes)")
  }
}

private func hex<T: BinaryInteger>(_ value: T) -> String { "0x" + String(value, radix: 16) }

extension [UInt8] {
  var hexBytes: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
