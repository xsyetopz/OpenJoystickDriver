import Dispatch
import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

let parsedArguments: HIDToolArguments
do {
  guard let parsed = try parseHIDToolArguments(Array(CommandLine.arguments.dropFirst())) else {
    printUsageAndExit(0)
  }
  parsedArguments = parsed
} catch {
  fputs("ERROR: \(error)\n", stderr)
  printUsageAndExit(2)
}

let list = parsedArguments.mode == .list
let dump = parsedArguments.mode == .dump
let open = parsedArguments.mode == .open
let serviceOpen = parsedArguments.flags.contains("--service-open")
let setReport = parsedArguments.flags.contains("--set-report")
let monitor = parsedArguments.mode == .monitor
let usbMonitor = parsedArguments.mode == .usbMonitor

func argValue(_ name: String) -> String? { parsedArguments.values[name] }

func intArg(_ name: String, default defaultValue: Int) -> Int {
  parsedArguments.int(name, default: defaultValue)
}

if let recordPath = argValue("--record-probe") {
  runControllerRecordProbe(
    recordPath: recordPath,
    seconds: intArg("--seconds", default: 30),
    validateOnly: parsedArguments.flags.contains("--validate-only")
  )
}

func runRawUSBMonitor() {
  let vendorID = UInt16(clamping: intArg("--vid", default: 0x045E))
  let productID = UInt16(clamping: intArg("--pid", default: 0))
  let explicitEndpoint = argValue("--endpoint").flatMap(parseInt).map { UInt8(clamping: $0) }
  let endpoints = explicitEndpoint.map { [$0] } ?? Array(UInt8(0x81)...UInt8(0x8F))
  let length = min(max(intArg("--length", default: 64), 1), 1024)
  let seconds = min(max(intArg("--seconds", default: 20), 1), 300)
  let timeout: UInt32 = explicitEndpoint == nil ? 100 : 250
  let exitCode = ExitCodeBox()
  let done = DispatchSemaphore(value: 0)

  Task {
    defer { done.signal() }
    let provider = OpenJoystickDriverUSBTransportProvider()
    do {
      let matches = try await provider.devices().filter {
        $0.vendorID == vendorID && (productID == 0 || $0.productID == productID)
      }
      print(
        "USB_MONITOR devices=\(matches.count) vid=0x\(String(vendorID, radix: 16))"
          + " pid=0x\(String(productID, radix: 16)) length=\(length) seconds=\(seconds)"
      )
      guard let device = matches.first else {
        fputs("ERROR: no matching raw USB service found\n", stderr)
        exitCode.value = 2
        return
      }
      print(
        "USB_DEVICE service=\(device.serviceID) location=\(device.locationID)"
          + " product=\(device.productName ?? "(unknown)")"
      )
      let session = try await provider.open(device, options: USBTransportOpenOptions())

      let deadline = Date().addingTimeInterval(TimeInterval(seconds))
      var packets = 0
      var disabledEndpoints = Set<UInt8>()
      while Date() < deadline {
        for endpoint in endpoints where Date() < deadline && !disabledEndpoints.contains(endpoint) {
          do {
            let bytes = try await session.readInterruptPacket(
              endpoint: endpoint,
              length: length,
              timeout: timeout
            )
            packets += 1
            print(
              "USB_REPORT endpoint=0x\(String(endpoint, radix: 16))"
                + " len=\(bytes.count) bytes=\(bytes.hexBytes)"
            )
            fflush(stdout)
          } catch USBTransportError.timeout { continue } catch {
            if explicitEndpoint == nil { disabledEndpoints.insert(endpoint) }
            print(
              "USB_ENDPOINT endpoint=0x\(String(endpoint, radix: 16))"
                + " result=error detail=\(error.localizedDescription)"
            )
          }
        }
        if disabledEndpoints.count == endpoints.count { break }
      }
      await session.close()
      print("USB_SUMMARY packets=\(packets) disabled_endpoints=\(disabledEndpoints.count)")
      exitCode.value = packets > 0 ? 0 : 3
    } catch {
      fputs("ERROR: raw USB monitor failed: \(error)\n", stderr)
      exitCode.value = 1
    }
  }

  done.wait()
  exit(exitCode.value)
}
if usbMonitor { runRawUSBMonitor() }

if monitor {
  let vid = intArg("--vid", default: 0x4F4A)
  let pid = intArg("--pid", default: 0x4447)
  let seconds = min(max(intArg("--seconds", default: 10), 1), 60)

  final class MonitorCounter {
    private let lock = NSLock()
    private(set) var values = 0
    private(set) var reports = 0

    func value(_ device: IOHIDDevice, _ value: IOHIDValue) {
      let element = IOHIDValueGetElement(value)
      let page = IOHIDElementGetUsagePage(element)
      let usage = IOHIDElementGetUsage(element)
      let intValue = IOHIDValueGetIntegerValue(value)
      lock.withLock { values += 1 }
      print(
        "VALUE page=0x\(String(page, radix: 16))"
          + " usage=0x\(String(usage, radix: 16)) value=\(intValue)"
      )
      fflush(stdout)
    }

    func report(
      _ type: IOHIDReportType,
      _ reportID: UInt32,
      _ report: UnsafePointer<UInt8>?,
      _ reportLength: CFIndex
    ) {
      lock.withLock { reports += 1 }
      print(
        "REPORT type=\(type.rawValue) id=\(reportID) len=\(reportLength)"
          + " bytes=\(hexString(report, count: reportLength))"
      )
      fflush(stdout)
    }

    func snapshot() -> (Int, Int) { lock.withLock { (values, reports) } }
  }

  let counter = MonitorCounter()
  let counterPtr = Unmanaged.passRetained(counter).toOpaque()
  defer { Unmanaged<MonitorCounter>.fromOpaque(counterPtr).release() }

  let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  IOHIDManagerSetDeviceMatching(
    mgr,
    [kIOHIDVendorIDKey as String: vid, kIOHIDProductIDKey as String: pid] as CFDictionary
  )

  let valueCallback: IOHIDValueCallback = { context, _, sender, value in
    guard let context, let sender else { return }
    let counter = Unmanaged<MonitorCounter>.fromOpaque(context).takeUnretainedValue()
    let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    counter.value(device, value)
  }
  IOHIDManagerRegisterInputValueCallback(mgr, valueCallback, counterPtr)

  let reportCallback: IOHIDReportCallback = { context, _, _, type, reportID, report, reportLength in
    guard let context else { return }
    let counter = Unmanaged<MonitorCounter>.fromOpaque(context).takeUnretainedValue()
    counter.report(type, reportID, report, reportLength)
  }
  IOHIDManagerRegisterInputReportCallback(mgr, reportCallback, counterPtr)
  IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

  let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
  guard openResult == kIOReturnSuccess else {
    fputs(
      "ERROR: IOHIDManagerOpen failed: "
        + "0x\(String(UInt32(bitPattern: openResult), radix: 16))\n",
      stderr
    )
    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    exit(1)
  }

  let devices = managerDevices(mgr)
  let elementsByDevice = devices.map { inputElements($0) }
  var lastPolledValues: [String: Int] = [:]

  print(
    "Monitoring \(devices.count) device(s), VID:0x\(String(vid, radix: 16))"
      + " PID:0x\(String(pid, radix: 16)), \(seconds)s"
  )
  for (idx, dev) in devices.enumerated() {
    print(
      "  product=\"\(strProp(dev, kIOHIDProductKey as String) ?? "(unknown)")\""
        + " transport=\(strProp(dev, kIOHIDTransportKey as String) ?? "(null)")"
        + " elements=\(elementsByDevice[idx].count)"
    )
  }
  if devices.isEmpty { printMonitorNoDeviceHint(vid: vid, pid: pid) }
  fflush(stdout)

  let end = Date().addingTimeInterval(TimeInterval(seconds))
  while Date() < end {
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
    for (deviceIndex, dev) in devices.enumerated() {
      for element in elementsByDevice[deviceIndex] {
        var value = unsafeBitCast(0, to: Unmanaged<IOHIDValue>.self)
        let result = IOHIDDeviceGetValue(dev, element, &value)
        guard result == kIOReturnSuccess else { continue }
        let intValue = IOHIDValueGetIntegerValue(value.takeUnretainedValue())
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let cookie = IOHIDElementGetCookie(element)
        let key = "\(deviceIndex):\(cookie)"
        if lastPolledValues[key] != intValue {
          lastPolledValues[key] = intValue
          print(
            "POLL page=0x\(String(page, radix: 16))"
              + " usage=0x\(String(usage, radix: 16)) value=\(intValue)"
          )
          fflush(stdout)
        }
      }
    }
  }

  let (values, reports) = counter.snapshot()
  IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
  IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
  print("SUMMARY values=\(values) reports=\(reports)")
  exit(values > 0 || reports > 0 ? 0 : 3)
}

if list {
  let devs = enumerateDevices(matching: nil)
  for dev in devs {
    let vid = intProp(dev, kIOHIDVendorIDKey as String)
    let pid = intProp(dev, kIOHIDProductIDKey as String)
    let product = strProp(dev, kIOHIDProductKey as String) ?? "(unknown)"
    let transport = strProp(dev, kIOHIDTransportKey as String) ?? "(null)"
    let inSize = intProp(dev, kIOHIDMaxInputReportSizeKey as String)
    let outSize = intProp(dev, kIOHIDMaxOutputReportSizeKey as String)
    let primaryPage = intProp(dev, kIOHIDPrimaryUsagePageKey as String)
    let primaryUsage = intProp(dev, kIOHIDPrimaryUsageKey as String)
    print(
      "VID:0x\(String(vid, radix: 16)) PID:0x\(String(pid, radix: 16))" + " transport=\(transport)"
        + " primary=\(primaryPage):\(primaryUsage)" + " maxIn=\(inSize) maxOut=\(outSize)"
        + " product=\"\(product)\""
    )
  }
  exit(0)
}

if open {
  let vid = intArg("--vid", default: 0x045E)
  let pid = intArg("--pid", default: 0x028E)
  let devs = enumerateDevices(matching: [
    kIOHIDVendorIDKey as String: vid, kIOHIDProductIDKey as String: pid
  ])
  print(
    "Opening \(devs.count) device(s), VID:0x\(String(vid, radix: 16))"
      + " PID:0x\(String(pid, radix: 16))"
  )
  var failures = 0
  for dev in devs {
    let product = strProp(dev, kIOHIDProductKey as String) ?? "(unknown)"
    let transport = strProp(dev, kIOHIDTransportKey as String) ?? "(null)"
    let openDevice: IOHIDDevice
    if serviceOpen {
      let service = IOHIDDeviceGetService(dev)
      var entryID: UInt64 = 0
      let idResult = IORegistryEntryGetRegistryEntryID(service, &entryID)
      guard idResult == KERN_SUCCESS,
        let recreated = IOHIDDeviceCreate(kCFAllocatorDefault, service)
      else {
        print(
          "  product=\"\(product)\" transport=\(transport)"
            + " service-open=create-failed idResult=0x"
            + String(format: "%08x", UInt32(bitPattern: idResult))
        )
        failures += 1
        continue
      }
      print("  service DevSrvsID:\(entryID)")
      openDevice = recreated
    } else {
      openDevice = dev
    }
    let result = IOHIDDeviceOpen(openDevice, IOOptionBits(kIOHIDOptionsTypeNone))
    print(
      "  product=\"\(product)\" transport=\(transport)"
        + " open=0x\(String(format: "%08x", UInt32(bitPattern: result)))"
    )
    if result != kIOReturnSuccess {
      failures += 1
      continue
    }
    if setReport {
      let report: [UInt8] = [0x00, 0x08, 0x00, 180, 100, 0, 0, 0]
      let setResult = report.withUnsafeBufferPointer { pointer -> IOReturn in
        guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
        return IOHIDDeviceSetReport(
          openDevice,
          kIOHIDReportTypeOutput,
          CFIndex(0),
          baseAddress,
          report.count
        )
      }
      print("  setReport=0x\(String(format: "%08x", UInt32(bitPattern: setResult)))")
      if setResult != kIOReturnSuccess { failures += 1 }
    }
    IOHIDDeviceClose(openDevice, IOOptionBits(kIOHIDOptionsTypeNone))
  }
  exit(failures == 0 ? 0 : 3)
}

if dump {
  guard let vidS = argValue("--vid"), let pidS = argValue("--pid") else {
    fputs("ERROR: --dump requires --vid and --pid.\n", stderr)
    printUsageAndExit(2)
  }
  guard let vid = parseInt(vidS), let pid = parseInt(pidS) else {
    fputs("ERROR: Could not parse --vid/--pid.\n", stderr)
    exit(2)
  }
  let devs = enumerateDevices(matching: [
    kIOHIDVendorIDKey as String: vid, kIOHIDProductIDKey as String: pid
  ])
  guard let dev = devs.first else {
    fputs("ERROR: Device not found. Is it connected?\n", stderr)
    exit(1)
  }
  guard let desc = dataProp(dev, kIOHIDReportDescriptorKey as String) else {
    fputs("ERROR: Device has no report descriptor property.\n", stderr)
    exit(1)
  }
  let bytes = [UInt8](desc)
  print("Descriptor length: \(bytes.count) bytes")
  print("")
  print("--- Hex ---")
  print(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
  print("")
  print("--- Swift [UInt8] ---")
  print("let descriptor: [UInt8] = [")
  var line: [String] = []
  for (idx, b) in bytes.enumerated() {
    line.append(String(format: "0x%02X", b))
    if line.count == 12 || idx == bytes.count - 1 {
      print("  " + line.joined(separator: ", ") + (idx == bytes.count - 1 ? "" : ","))
      line.removeAll(keepingCapacity: true)
    }
  }
  print("]")
  exit(0)
}

printUsageAndExit(2)
