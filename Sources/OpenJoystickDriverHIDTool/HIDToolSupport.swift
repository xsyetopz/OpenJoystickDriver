import Dispatch
import Foundation
import IOKit
import IOKit.hid
import SwiftUSB

func parseInt(_ s: String) -> Int? {
  if s.hasPrefix("0x") || s.hasPrefix("0X") {
    return Int(s.dropFirst(2), radix: 16)
  }
  return Int(s)
}

func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Int ?? 0
}

func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? String
}

func dataProp(_ dev: IOHIDDevice, _ key: String) -> Data? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Data
}

func hexString(_ bytes: UnsafePointer<UInt8>?, count: Int) -> String {
  guard let bytes, count > 0 else { return "" }
  return (0..<count).map { String(format: "%02x", bytes[$0]) }.joined(separator: " ")
}

final class ExitCodeBox: @unchecked Sendable {
  private let lock = NSLock()
  private var rawValue: Int32 = 0

  var value: Int32 {
    get { lock.withLock { rawValue } }
    set { lock.withLock { rawValue = newValue } }
  }
}

func enumerateDevices(matching: [String: Any]?) -> [IOHIDDevice] {
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

func managerDevices(_ mgr: IOHIDManager) -> [IOHIDDevice] {
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

func inputElements(_ dev: IOHIDDevice) -> [IOHIDElement] {
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

func printMonitorNoDeviceHint(vid: Int, pid: Int) {
  let vendorDevices = enumerateDevices(matching: [kIOHIDVendorIDKey as String: vid])
  print(
    "HINT no exact IOHID match; same-vendor devices=\(vendorDevices.count)"
  )
  for dev in vendorDevices {
    let candidatePID = intProp(dev, kIOHIDProductIDKey as String)
    let product = strProp(dev, kIOHIDProductKey as String) ?? "(unknown)"
    let transport = strProp(dev, kIOHIDTransportKey as String) ?? "(null)"
    let primaryPage = intProp(dev, kIOHIDPrimaryUsagePageKey as String)
    let primaryUsage = intProp(dev, kIOHIDPrimaryUsageKey as String)
    print(
      "HINT_DEVICE VID:0x\(String(vid, radix: 16))"
        + " PID:0x\(String(candidatePID, radix: 16))"
        + " transport=\(transport) primary=\(primaryPage):\(primaryUsage)"
        + " product=\"\(product)\""
    )
  }
  print(
    "HINT raw USB fallback: OJD_USE_LOCAL_SWIFTUSB=1 swift run "
      + "OpenJoystickDriverHIDTool --usb-monitor --vid 0x\(String(vid, radix: 16))"
      + " --pid 0x\(String(pid, radix: 16)) --interface 0 --length 64 --seconds 20"
  )
}

func printUsageAndExit(_ code: Int32) -> Never {
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
