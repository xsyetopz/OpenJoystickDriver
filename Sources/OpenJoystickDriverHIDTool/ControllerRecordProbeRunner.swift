import Dispatch
import Foundation
import OpenJoystickDriverKit
import SwiftUSB

private let controllerRecordProbeKeepAliveIntervalNanoseconds: UInt64 = 4_000_000_000

func runControllerRecordProbe(
  recordPath: String,
  seconds: Int,
  detachKernel: Bool,
  validateOnly: Bool
) -> Never {
  let exitCode = ExitCodeBox()
  let done = DispatchSemaphore(value: 0)

  Task {
    defer { done.signal() }

    do {
      let plan = try ControllerRecordProbePlan(contentsOf: URL(fileURLWithPath: recordPath))
      let inputEndpoint = plan.transportProfile.inputEndpoint
      let outputEndpoint = plan.transportProfile.outputEndpoint
      let startupNames = plan.startupPackets.map(\.rawValue).joined(separator: ",")
      print(
        "RECORD identity=\"\(plan.name)\"" + " vid=\(plan.vendorID) pid=\(plan.productID)"
          + " driver=\(plan.driver.rawValue)" + " interface=\(plan.interfaceNumber)"
          + " in=\(hex(inputEndpoint)) out=\(hex(outputEndpoint))"
          + " configuration=\(plan.transportProfile.needsSetConfiguration ? "set1" : "current")"
          + " startup=\(startupNames.isEmpty ? "none" : startupNames)"
      )

      if validateOnly {
        print("RECORD_VALIDATION result=valid")
        exitCode.value = 0
        return
      }

      let devices = try await USBDevice.findAll(
        vendorId: plan.vendorID,
        productId: plan.productID,
        deviceClass: nil
      )
      print("USB_MATCHES count=\(devices.count)")
      guard let device = devices.first else {
        fputs("ERROR: no USB device matches the record VID/PID\n", stderr)
        exitCode.value = 2
        return
      }

      print(
        "USB_DEVICE bus=\(device.bus) address=\(device.address)"
          + " class=\(hex(device.deviceClass))" + " subclass=\(hex(device.deviceSubClass))"
          + " protocol=\(hex(device.deviceProtocol))"
      )
      if let manufacturer = try? device.getManufacturer() {
        print("USB_STRING manufacturer=\(manufacturer)")
      }
      if let product = try? device.getProduct() { print("USB_STRING product=\(product)") }

      let handle = try device.open()
      var claimedInterface = false
      defer { if claimedInterface { try? handle.releaseInterface(plan.interfaceNumber) } }

      if plan.transportProfile.needsSetConfiguration {
        let currentConfiguration = (try? handle.getConfiguration()) ?? 0
        if currentConfiguration != 1 {
          try handle.setConfiguration(1)
          print("USB_CONFIGURATION value=1 result=set")
        } else {
          print("USB_CONFIGURATION value=1 result=already-set")
        }
      }

      if detachKernel {
        do {
          try handle.detachKernelDriver(interface: plan.interfaceNumber)
          print("USB_DETACH interface=\(plan.interfaceNumber) result=detached")
        } catch let error as USBError where error.isNotFound || error.isNotSupported {
          print(
            "USB_DETACH interface=\(plan.interfaceNumber)" + " result=not-needed code=\(error.code)"
          )
        }
      }

      try handle.claimInterface(plan.interfaceNumber)
      claimedInterface = true
      print("USB_CLAIM interface=\(plan.interfaceNumber) result=claimed")

      let parser = plan.makeParser()
      try await parser.performHandshake(handle: handle)
      print("RECORD_HANDSHAKE driver=\(plan.driver.rawValue) result=complete")

      if let startupOutput = parser as? any USBStartupOutputProvider {
        for packet in startupOutput.usbStartupOutputPackets() {
          _ = try handle.interruptTransfer(endpoint: outputEndpoint, data: packet, timeout: 2_000)
          print("USB_TX endpoint=\(hex(outputEndpoint)) bytes=\(packet.hexBytes)")
        }
      }

      if plan.transportProfile.postHandshakeSettleNanoseconds > 0 {
        try await Task.sleep(nanoseconds: plan.transportProfile.postHandshakeSettleNanoseconds)
      }

      let deadline = Date().addingTimeInterval(TimeInterval(seconds))
      var lastKeepAlive = DispatchTime.now().uptimeNanoseconds
      var packetCount = 0
      var eventCount = 0
      var parseErrorCount = 0

      while Date() < deadline {
        let now = DispatchTime.now().uptimeNanoseconds
        if now &- lastKeepAlive >= controllerRecordProbeKeepAliveIntervalNanoseconds {
          lastKeepAlive = now
          do {
            try parser.keepAlive(handle: handle)
            print("USB_KEEPALIVE result=sent")
          } catch { print("USB_KEEPALIVE result=error detail=\(error.localizedDescription)") }
        }

        do {
          let bytes = try handle.readInterrupt(endpoint: inputEndpoint, length: 64, timeout: 250)
          packetCount += 1
          print(
            "USB_RX endpoint=\(hex(inputEndpoint))" + " len=\(bytes.count) bytes=\(bytes.hexBytes)"
          )
          do {
            let events = try parser.parse(data: Data(bytes))
            if let lifecycle = parser as? any ControllerInputConnectionLifecycle,
              let state = lifecycle.consumeInputConnectionStateChange()
            {
              print("CONTROLLER_CONNECTION state=\(String(describing: state))")
              if let output = parser as? any USBInputConnectionOutputProvider {
                for packet in output.usbInputConnectionOutputPackets(for: state) {
                  _ = try handle.interruptTransfer(
                    endpoint: outputEndpoint,
                    data: packet,
                    timeout: 2_000
                  )
                  print("USB_TX endpoint=\(hex(outputEndpoint)) bytes=\(packet.hexBytes)")
                }
              }
            }
            eventCount += events.count
            for event in events { print("EVENT \(String(describing: event))") }
          } catch {
            parseErrorCount += 1
            print("PARSE_ERROR detail=\(error.localizedDescription)")
          }
          fflush(stdout)
        } catch let error as USBError where error.isTimeout { continue }
      }

      print(
        "RECORD_SUMMARY packets=\(packetCount)"
          + " events=\(eventCount) parse_errors=\(parseErrorCount)"
      )
      exitCode.value = packetCount > 0 ? 0 : 3
    } catch {
      fputs("ERROR: record probe failed: \(error.localizedDescription)\n", stderr)
      exitCode.value = 1
    }
  }

  done.wait()
  exit(exitCode.value)
}

private func hex<T: BinaryInteger>(_ value: T) -> String { "0x" + String(value, radix: 16) }

extension [UInt8] {
  var hexBytes: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
