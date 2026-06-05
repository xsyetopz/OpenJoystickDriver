import Dispatch
import Foundation
import IOKit
import IOKit.hid
import SwiftUSB

private func parseInt(_ s: String) -> Int? {
  if s.hasPrefix("0x") || s.hasPrefix("0X") {
    return Int(s.dropFirst(2), radix: 16)
  }
  return Int(s)
}

private func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Int ?? 0
}

private func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? String
}

private func dataProp(_ dev: IOHIDDevice, _ key: String) -> Data? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Data
}

private func hexString(_ bytes: UnsafePointer<UInt8>?, count: Int) -> String {
  guard let bytes, count > 0 else { return "" }
  return (0..<count).map { String(format: "%02x", bytes[$0]) }.joined(separator: " ")
}

private final class ExitCodeBox: @unchecked Sendable {
  private let lock = NSLock()
  private var rawValue: Int32 = 0

  var value: Int32 {
    get { lock.withLock { rawValue } }
    set { lock.withLock { rawValue = newValue } }
  }
}

private func enumerateDevices(matching: [String: Any]?) -> [IOHIDDevice] {
  let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  if let matching {
    IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
  } else {
    IOHIDManagerSetDeviceMatching(mgr, nil)
  }
  _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
  defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
  return Array(((IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []).sorted {
    let a =
      intProp($0, kIOHIDVendorIDKey as String) * 0x1_0000
      + intProp($0, kIOHIDProductIDKey as String)
    let b =
      intProp($1, kIOHIDVendorIDKey as String) * 0x1_0000
      + intProp($1, kIOHIDProductIDKey as String)
    return a < b
  })
}

private func managerDevices(_ mgr: IOHIDManager) -> [IOHIDDevice] {
  guard let rawDevices = IOHIDManagerCopyDevices(mgr) else { return [] }
  let count = CFSetGetCount(rawDevices)
  guard count > 0 else { return [] }
  let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
  defer { values.deallocate() }
  CFSetGetValues(rawDevices, values)
  return (0..<count).compactMap { idx in
    guard let value = values[idx] else { return nil }
    return unsafeBitCast(value, to: IOHIDDevice.self)
  }.sorted {
    let a =
      intProp($0, kIOHIDVendorIDKey as String) * 0x1_0000
      + intProp($0, kIOHIDProductIDKey as String)
    let b =
      intProp($1, kIOHIDVendorIDKey as String) * 0x1_0000
      + intProp($1, kIOHIDProductIDKey as String)
    return a < b
  }
}

private func inputElements(_ dev: IOHIDDevice) -> [IOHIDElement] {
  guard let rawElements = IOHIDDeviceCopyMatchingElements(
    dev,
    nil,
    IOOptionBits(kIOHIDOptionsTypeNone)
  ) as? [IOHIDElement] else {
    return []
  }
  return rawElements.filter { element in
    let type = IOHIDElementGetType(element)
    return type == kIOHIDElementTypeInput_Misc
      || type == kIOHIDElementTypeInput_Button
      || type == kIOHIDElementTypeInput_Axis
  }
}

private func printUsageAndExit(_ code: Int32) -> Never {
  fputs(
    """
    OpenJoystickDriverHIDTool

    Usage:
      OpenJoystickDriverHIDTool --list
      OpenJoystickDriverHIDTool --dump --vid 0x045e --pid 0x02ea
      OpenJoystickDriverHIDTool --open --vid 0x045e --pid 0x028e [--service-open] [--set-report]
      OpenJoystickDriverHIDTool --monitor [--vid 0x4f4a --pid 0x4447] [--seconds 10]
      OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000\
        [--endpoint 0x81] [--interface 0] [--length 64] [--seconds 20] [--detach]

    Options:
      --list           List HID devices (vid/pid/product/transport + report sizes).
      --dump           Dump the report descriptor for one device (as hex and Swift [UInt8]).
      --open           Directly call IOHIDDeviceOpen on matching devices.
      --service-open   With --open, recreate the device from IOHIDDeviceGetService first.
      --set-report     With --open, send one Xbox 360-style rumble output report.
      --monitor        Open matching HID devices and print input value/report callbacks.
      --usb-monitor    Claim one USB interface and print raw interrupt IN packets.
      --detach         With --usb-monitor, try detaching the kernel driver first.
      --vid <int>      Vendor ID (decimal or 0x... hex).
      --pid <int>      Product ID (decimal or 0x... hex).
      --interface <n>  USB interface number for --usb-monitor (default: 0).
      --endpoint <n>   Interrupt IN endpoint for --usb-monitor; omitted sweeps 0x81...0x8f.
      --length <n>     Read length for --usb-monitor (default: 64, max: 1024).
      --seconds <int>  Monitor duration in seconds (default: 10, max: 60).
      --help           Show this help.

    """,
    stderr
  )
  exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") { printUsageAndExit(0) }

let list = args.contains("--list")
let dump = args.contains("--dump")
let open = args.contains("--open")
let serviceOpen = args.contains("--service-open")
let setReport = args.contains("--set-report")
let monitor = args.contains("--monitor")
let usbMonitor = args.contains("--usb-monitor")
let detachKernel = args.contains("--detach")

func argValue(_ name: String) -> String? {
  guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
  return args[idx + 1]
}

func intArg(_ name: String, default defaultValue: Int) -> Int {
  guard let raw = argValue(name), let parsed = parseInt(raw) else { return defaultValue }
  return parsed
}


func runRawUSBMonitor() {
  let vid = UInt16(clamping: intArg("--vid", default: 0x045E))
  let pid = UInt16(clamping: intArg("--pid", default: 0))
  let interfaceNumber = intArg("--interface", default: 0)
  let explicitEndpoint = argValue("--endpoint").flatMap(parseInt).map { UInt8(clamping: $0) }
  let endpoints = explicitEndpoint.map { [$0] } ?? Array(UInt8(0x81)...UInt8(0x8F))
  let length = min(max(intArg("--length", default: 64), 1), 1024)
  let seconds = min(max(intArg("--seconds", default: 20), 1), 300)
  let timeoutMs: UInt32 = explicitEndpoint == nil ? 100 : 250
  let exitCode = ExitCodeBox()
  let done = DispatchSemaphore(value: 0)

  Task {
    defer { done.signal() }
    do {
      let devices = try await USBDevice.findAll(vendorId: vid, productId: pid, deviceClass: nil)
      let endpointDescription = explicitEndpoint.map { "0x" + String($0, radix: 16) }
        ?? "sweep:0x81-0x8f"
      print(
        "USB_MONITOR devices=\(devices.count) vid=0x\(String(vid, radix: 16))"
          + " pid=0x\(String(pid, radix: 16)) interface=\(interfaceNumber)"
          + " endpoint=\(endpointDescription) length=\(length) seconds=\(seconds)"
      )
      guard let device = devices.first else {
        fputs("ERROR: no matching USB device found\n", stderr)
        exitCode.value = 2
        return
      }

      print(
        "USB_DEVICE bus=\(device.bus) address=\(device.address)"
          + " class=0x\(String(device.deviceClass, radix: 16))"
          + " subclass=0x\(String(device.deviceSubClass, radix: 16))"
          + " protocol=0x\(String(device.deviceProtocol, radix: 16))"
      )
      if let manufacturer = try? device.getManufacturer() {
        print("USB_STRING manufacturer=\(manufacturer)")
      }
      if let product = try? device.getProduct() { print("USB_STRING product=\(product)") }
      if let serial = try? device.getSerialNumber() { print("USB_STRING serial=\(serial)") }

      let handle = try device.open()
      if detachKernel {
        do {
          try handle.detachKernelDriver(interface: interfaceNumber)
          print("USB_DETACH interface=\(interfaceNumber) result=detached")
        } catch let error as USBError where error.isNotFound || error.isNotSupported {
          print("USB_DETACH interface=\(interfaceNumber) result=not-needed code=\(error.code)")
        }
      }
      try handle.claimInterface(interfaceNumber)
      print("USB_CLAIM interface=\(interfaceNumber) result=claimed")
      if explicitEndpoint == nil {
        print("USB_ENDPOINT_SWEEP candidates=0x81...0x8f timeout_ms=\(timeoutMs)")
      }

      let end = Date().addingTimeInterval(TimeInterval(seconds))
      var packets = 0
      var disabledEndpoints = Set<UInt8>()
      while Date() < end {
        for endpoint in endpoints where Date() < end && !disabledEndpoints.contains(endpoint) {
          do {
            let bytes = try handle.readInterrupt(
              endpoint: endpoint,
              length: length,
              timeout: timeoutMs
            )
            packets += 1
            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            print(
              "USB_REPORT endpoint=0x\(String(endpoint, radix: 16))"
                + " len=\(bytes.count) bytes=\(hex)"
            )
            fflush(stdout)
          } catch let error as USBError where error.isTimeout {
            continue
          } catch let error as USBError {
            if explicitEndpoint == nil { disabledEndpoints.insert(endpoint) }
            print(
              "USB_ENDPOINT endpoint=0x\(String(endpoint, radix: 16))"
                + " result=error code=\(error.code)"
            )
            fflush(stdout)
          }
        }
        if disabledEndpoints.count == endpoints.count { break }
      }
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

    func snapshot() -> (Int, Int) {
      lock.withLock { (values, reports) }
    }
  }

  let counter = MonitorCounter()
  let counterPtr = Unmanaged.passRetained(counter).toOpaque()
  defer { Unmanaged<MonitorCounter>.fromOpaque(counterPtr).release() }

  let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  IOHIDManagerSetDeviceMatching(mgr, [
    kIOHIDVendorIDKey as String: vid,
    kIOHIDProductIDKey as String: pid,
  ] as CFDictionary)

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
      "VID:0x\(String(vid, radix: 16)) PID:0x\(String(pid, radix: 16))"
        + " transport=\(transport)"
        + " primary=\(primaryPage):\(primaryUsage)"
        + " maxIn=\(inSize) maxOut=\(outSize)"
        + " product=\"\(product)\""
    )
  }
  exit(0)
}

if open {
  let vid = intArg("--vid", default: 0x045E)
  let pid = intArg("--pid", default: 0x028E)
  let devs = enumerateDevices(matching: [
    kIOHIDVendorIDKey as String: vid,
    kIOHIDProductIDKey as String: pid,
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
    kIOHIDVendorIDKey as String: vid,
    kIOHIDProductIDKey as String: pid,
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
