import Dispatch
import Foundation
import IOKit
import IOKit.hid

func parseInt(_ s: String) -> Int? {
  if s.hasPrefix("0x") || s.hasPrefix("0X") { return Int(s.dropFirst(2), radix: 16) }
  return Int(s)
}

enum HIDToolMode: String, CaseIterable {
  case list = "--list"
  case dump = "--dump"
  case open = "--open"
  case monitor = "--monitor"
  case usbMonitor = "--usb-monitor"
  case recordProbe = "--record-probe"
}

struct HIDToolArguments {
  let mode: HIDToolMode
  let values: [String: String]
  let flags: Set<String>

  func int(_ name: String, default defaultValue: Int) -> Int {
    values[name].flatMap(parseInt) ?? defaultValue
  }
}

enum HIDToolArgumentError: Error, CustomStringConvertible {
  case message(String)

  var description: String {
    switch self {
    case .message(let message): message
    }
  }
}

func parseHIDToolArguments(_ arguments: [String]) throws -> HIDToolArguments? {
  if arguments == ["-h"] || arguments == ["--help"] { return nil }

  let valueOptions = Set(["--vid", "--pid", "--endpoint", "--length", "--seconds"])
  let booleanOptions = Set(["--service-open", "--set-report", "--validate-only"])
  let knownOptions = valueOptions.union(booleanOptions).union(HIDToolMode.allCases.map(\.rawValue))
  var values: [String: String] = [:]
  var flags = Set<String>()
  var modes: [HIDToolMode] = []
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    guard knownOptions.contains(argument) else {
      throw HIDToolArgumentError.message("unknown option '\(argument)'")
    }
    guard !flags.contains(argument), values[argument] == nil else {
      throw HIDToolArgumentError.message("duplicate option '\(argument)'")
    }
    if let mode = HIDToolMode(rawValue: argument) {
      modes.append(mode)
      if mode == .recordProbe {
        guard index + 1 < arguments.count, !knownOptions.contains(arguments[index + 1]) else {
          throw HIDToolArgumentError.message("missing value for '--record-probe'")
        }
        values[argument] = arguments[index + 1]
        index += 2
        continue
      }
      flags.insert(argument)
      index += 1
      continue
    }
    if valueOptions.contains(argument) {
      guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") else {
        throw HIDToolArgumentError.message("missing value for '\(argument)'")
      }
      values[argument] = arguments[index + 1]
      index += 2
    } else {
      flags.insert(argument)
      index += 1
    }
  }

  guard modes.count == 1, let mode = modes.first else {
    let message = modes.isEmpty ? "missing mode selector" : "multiple mode selectors"
    throw HIDToolArgumentError.message(message)
  }

  let owned: Set<String>
  switch mode {
  case .list: owned = []
  case .dump: owned = ["--vid", "--pid"]
  case .open: owned = ["--vid", "--pid", "--service-open", "--set-report"]
  case .monitor: owned = ["--vid", "--pid", "--seconds"]
  case .usbMonitor: owned = ["--vid", "--pid", "--endpoint", "--length", "--seconds"]
  case .recordProbe: owned = ["--seconds", "--validate-only"]
  }
  let suppliedOptions = Set(values.keys).union(flags).subtracting([mode.rawValue])
  if let option = suppliedOptions.subtracting(owned).min() {
    throw HIDToolArgumentError.message("option '\(option)' is not valid with '\(mode.rawValue)'")
  }

  func validate(_ name: String, range: ClosedRange<Int>) throws {
    guard let raw = values[name] else { return }
    guard let value = parseInt(raw) else {
      throw HIDToolArgumentError.message("malformed value '\(raw)' for '\(name)'")
    }
    guard range.contains(value) else {
      let bounds = "\(range.lowerBound)...\(range.upperBound)"
      throw HIDToolArgumentError.message("value for '\(name)' is out of range \(bounds)")
    }
  }

  try validate("--vid", range: 0...0xFFFF)
  try validate("--pid", range: 0...0xFFFF)
  if mode == .monitor { try validate("--seconds", range: 1...60) }
  if mode == .usbMonitor || mode == .recordProbe { try validate("--seconds", range: 1...300) }
  if mode == .usbMonitor {
    try validate("--endpoint", range: 0...255)
    try validate("--length", range: 1...1024)
  }
  if mode == .dump {
    for required in ["--vid", "--pid"] where values[required] == nil {
      throw HIDToolArgumentError.message("'--dump' requires '\(required)'")
    }
  }

  return HIDToolArguments(mode: mode, values: values, flags: flags)
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
  return Array(
    ((IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []).sorted {
      let a =
        intProp($0, kIOHIDVendorIDKey as String) * 0x1_0000
        + intProp($0, kIOHIDProductIDKey as String)
      let b =
        intProp($1, kIOHIDVendorIDKey as String) * 0x1_0000
        + intProp($1, kIOHIDProductIDKey as String)
      return a < b
    }
  )
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
  guard
    let rawElements = IOHIDDeviceCopyMatchingElements(dev, nil, IOOptionBits(kIOHIDOptionsTypeNone))
      as? [IOHIDElement]
  else { return [] }
  return rawElements.filter { element in
    let type = IOHIDElementGetType(element)
    return type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Button
      || type == kIOHIDElementTypeInput_Axis
  }
}

func printMonitorNoDeviceHint(vid: Int, pid: Int) {
  let vendorDevices = enumerateDevices(matching: [kIOHIDVendorIDKey as String: vid])
  print("HINT no exact IOHID match; same-vendor devices=\(vendorDevices.count)")
  for dev in vendorDevices {
    let candidatePID = intProp(dev, kIOHIDProductIDKey as String)
    let product = strProp(dev, kIOHIDProductKey as String) ?? "(unknown)"
    let transport = strProp(dev, kIOHIDTransportKey as String) ?? "(null)"
    let primaryPage = intProp(dev, kIOHIDPrimaryUsagePageKey as String)
    let primaryUsage = intProp(dev, kIOHIDPrimaryUsageKey as String)
    print(
      "HINT_DEVICE VID:0x\(String(vid, radix: 16))" + " PID:0x\(String(candidatePID, radix: 16))"
        + " transport=\(transport) primary=\(primaryPage):\(primaryUsage)"
        + " product=\"\(product)\""
    )
  }
  print(
    "HINT raw USB diagnostics: swift run "
      + "OpenJoystickDriverHIDTool --usb-monitor --vid 0x\(String(vid, radix: 16))"
      + " --pid 0x\(String(pid, radix: 16)) --length 64 --seconds 20"
  )
}

func printUsageAndExit(_ code: Int32) -> Never {
  fputs(
    """
    OpenJoystickDriverHIDTool. Internal hardware diagnostic utility.

    Use `./scripts/ojd diagnose` for supported workflows. Run this utility directly
    only for focused hardware debugging.

    Usage:
      OpenJoystickDriverHIDTool --list
      OpenJoystickDriverHIDTool --dump --vid 0x045e --pid 0x02ea
      OpenJoystickDriverHIDTool --open --vid 0x045e --pid 0x028e [--service-open] [--set-report]
      OpenJoystickDriverHIDTool --monitor [--vid 0x4f4a --pid 0x4447] [--seconds 10]
      OpenJoystickDriverHIDTool --usb-monitor --vid 0x045e --pid 0x0000
        [--endpoint 0x81] [--length 64] [--seconds 20]
      OpenJoystickDriverHIDTool --record-probe <record.json>
        [--seconds 30] [--validate-only]

    Options:
      --list           List HID devices (vid/pid/product/transport + report sizes).
      --dump           Dump the report descriptor for one device (as hex and Swift [UInt8]).
      --open           Directly call IOHIDDeviceOpen on matching devices.
      --service-open   With --open, recreate the device from IOHIDDeviceGetService first.
      --set-report     With --open, send one Xbox 360-style rumble output report.
      --monitor        Open matching HID devices and print input value/report callbacks.
      --usb-monitor    Open one raw USB service and print interrupt IN packets.
      --record-probe  Validate and exercise one controller record through the USB facade.
      --validate-only  Validate --record-probe input without opening physical hardware.
      --vid <int>      Vendor ID (decimal or 0x... hex).
      --pid <int>      Product ID (decimal or 0x... hex).
      --endpoint <n>   Interrupt IN endpoint for --usb-monitor; omitted sweeps 0x81...0x8f.
      --length <n>     Read length for --usb-monitor (default: 64, max: 1024).
      --seconds <int>  Monitor duration in seconds (default varies, max: 300).
      -h, --help       Show this help.

    """,
    stderr
  )
  exit(code)
}
