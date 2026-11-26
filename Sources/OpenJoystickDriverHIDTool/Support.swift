import Dispatch
import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform

/// Parses decimal text, or hex text with a `0x` prefix, as an integer.
func parseInt(_ s: String) -> Int? {
  if s.hasPrefix("0x") || s.hasPrefix("0X") { return Int(s.dropFirst(2), radix: 16) }
  return Int(s)
}

/// The mode that the command line selects.
enum HIDToolMode: String, CaseIterable {
  /// List the HID devices.
  case list = "--list"
  /// Dump the report descriptor of a device.
  case dump = "--dump"
  /// Print the input elements of a device as JSON.
  case dumpElements = "--dump-elements"
  /// Open matching HID devices directly.
  case open = "--open"
  /// Print the input callbacks of matching HID devices.
  case monitor = "--monitor"
  /// Print the interrupt IN packets of a raw USB device.
  case usbMonitor = "--usb-monitor"
  /// Validate and exercise a controller record through the USB facade.
  case recordProbe = "--record-probe"
  /// Print the USB descriptor facts of an authorized device without opening it.
  case usbPassive = "--usb-passive"
}

/// The parsed command line of the tool.
struct HIDToolArguments {
  /// The selected mode.
  let mode: HIDToolMode
  /// The options that carry a value, by option name.
  let values: [String: String]
  /// The options that carry no value.
  let flags: Set<String>

  /// Returns the integer value of the option `name`, or `defaultValue` when it is absent or not a
  /// number.
  func int(_ name: String, default defaultValue: Int) -> Int {
    values[name].flatMap(parseInt) ?? defaultValue
  }
}

/// The failure of parsing the command line.
enum HIDToolArgumentError: Error, CustomStringConvertible {
  /// A failure with the text to print.
  case message(String)

  /// The text of the failure.
  var description: String {
    switch self {
    case .message(let message): message
    }
  }
}

/// Parses the command line into a mode and its options.
///
/// - Returns: The arguments, or nil when the command line asks for help.
/// - Throws: ``HIDToolArgumentError`` for an unknown or duplicate option, a missing value, a
///   missing or repeated mode, or an option that the mode does not use.
func parseHIDToolArguments(_ arguments: [String]) throws -> HIDToolArguments? {
  if arguments == ["-h"] || arguments == ["--help"] { return nil }

  let scan = try scanHIDToolOptions(arguments)
  guard scan.modes.count == 1, let mode = scan.modes.first else {
    let message = scan.modes.isEmpty ? "missing mode selector" : "multiple mode selectors"
    throw HIDToolArgumentError.message(message)
  }

  let suppliedOptions = Set(scan.values.keys).union(scan.flags).subtracting([mode.rawValue])
  if let option = suppliedOptions.subtracting(ownedHIDToolOptions(of: mode)).min() {
    throw HIDToolArgumentError.message("option '\(option)' is not valid with '\(mode.rawValue)'")
  }
  try validateHIDToolValues(of: mode, scan.values)

  return HIDToolArguments(mode: mode, values: scan.values, flags: scan.flags)
}

/// The options that take a value.
private let hidToolValueOptions: Set<String> = [
  "--vid", "--pid", "--endpoint", "--length", "--seconds", "--send", "--out-endpoint",
]

/// The options that stand alone.
private let hidToolBooleanOptions: Set<String> = [
  "--service-open", "--set-report", "--validate-only",
]

/// What one pass over the command line found.
private struct HIDToolScan {
  /// The options that carry a value, by option name.
  var values: [String: String] = [:]
  /// The options that carry no value, mode selectors included.
  var flags = Set<String>()
  /// The mode selectors, in the order given.
  var modes: [HIDToolMode] = []
}

/// Splits the command line into value options, flags, and mode selectors.
///
/// `--record-probe` is a mode selector that also takes the record path as its value.
private func scanHIDToolOptions(_ arguments: [String]) throws -> HIDToolScan {
  let knownOptions = hidToolValueOptions.union(hidToolBooleanOptions)
    .union(HIDToolMode.allCases.map(\.rawValue))
  var scan = HIDToolScan()
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    guard knownOptions.contains(argument) else {
      throw HIDToolArgumentError.message("unknown option '\(argument)'")
    }
    guard !scan.flags.contains(argument), scan.values[argument] == nil else {
      throw HIDToolArgumentError.message("duplicate option '\(argument)'")
    }
    let mode = HIDToolMode(rawValue: argument)
    if let mode { scan.modes.append(mode) }
    let takesValue = mode == .recordProbe || (mode == nil && hidToolValueOptions.contains(argument))
    guard takesValue else {
      scan.flags.insert(argument)
      index += 1
      continue
    }
    let valueIndex = index + 1
    // A record path may start with `-`; it only must not be another option.
    let valid =
      valueIndex < arguments.count
      && (mode == .recordProbe
        ? !knownOptions.contains(arguments[valueIndex]) : !arguments[valueIndex].hasPrefix("-"))
    guard valid else {
      throw HIDToolArgumentError.message("missing value for '\(argument)'")
    }
    scan.values[argument] = arguments[valueIndex]
    index += 2
  }
  return scan
}

/// The options, besides the selector itself, that `mode` uses.
private func ownedHIDToolOptions(of mode: HIDToolMode) -> Set<String> {
  switch mode {
  case .list: []
  case .dump, .dumpElements, .usbPassive: ["--vid", "--pid"]
  case .open: ["--vid", "--pid", "--service-open", "--set-report"]
  case .monitor: ["--vid", "--pid", "--seconds"]
  case .usbMonitor: hidToolValueOptions
  case .recordProbe: ["--seconds", "--validate-only"]
  }
}

/// Checks that the option `name`, when given, is a number inside `range`.
private func validateHIDToolValue(
  _ name: String,
  in values: [String: String],
  range: ClosedRange<Int>
) throws {
  guard let raw = values[name] else { return }
  guard let value = parseInt(raw) else {
    throw HIDToolArgumentError.message("malformed value '\(raw)' for '\(name)'")
  }
  guard range.contains(value) else {
    let bounds = "\(range.lowerBound)...\(range.upperBound)"
    throw HIDToolArgumentError.message("value for '\(name)' is out of range \(bounds)")
  }
}

/// Checks the ranges of the values that `mode` takes and the options that it requires.
private func validateHIDToolValues(of mode: HIDToolMode, _ values: [String: String]) throws {
  try validateHIDToolValue("--vid", in: values, range: 0...0xFFFF)
  try validateHIDToolValue("--pid", in: values, range: 0...0xFFFF)
  if mode == .monitor { try validateHIDToolValue("--seconds", in: values, range: 1...60) }
  if mode == .usbMonitor || mode == .recordProbe {
    try validateHIDToolValue("--seconds", in: values, range: 1...300)
  }
  if mode == .usbMonitor { try validateUSBMonitorValues(mode, values) }
  if mode == .dump || mode == .dumpElements || mode == .usbPassive || mode == .open {
    for required in ["--vid", "--pid"] where values[required] == nil {
      throw HIDToolArgumentError.message("'\(mode.rawValue)' requires '\(required)'")
    }
  }
}

/// Checks the endpoint, length, and packet options of `--usb-monitor`.
private func validateUSBMonitorValues(_ mode: HIDToolMode, _ values: [String: String]) throws {
  if values["--vid"] == nil {
    throw HIDToolArgumentError.message("'\(mode.rawValue)' requires '--vid'")
  }
  try validateHIDToolValue("--endpoint", in: values, range: 0...255)
  try validateHIDToolValue("--length", in: values, range: 1...1024)
  try validateHIDToolValue("--out-endpoint", in: values, range: 0x01...0x0F)
  guard let packets = values["--send"] else { return }
  guard parseUSBPackets(packets) != nil else {
    throw HIDToolArgumentError.message("malformed value '\(packets)' for '--send'")
  }
  guard values["--out-endpoint"] != nil else {
    throw HIDToolArgumentError.message("'--send' requires '--out-endpoint'")
  }
}

/// The packets of `text`: each one 1 to 64 hex pairs, separated from the next by `;`, such as
/// `05 20 00 01 00; 0A 20 00 03 00 01 14`; nil when any packet is malformed.
func parseUSBPackets(_ text: String) -> [[UInt8]]? {
  let packets = text.split(separator: ";").map { ControllerRawOutput.parseHex(String($0)) }
  guard !packets.isEmpty else { return nil }
  let parsed = packets.compactMap { $0 }
  guard parsed.count == packets.count,
    parsed.allSatisfy({ $0.count <= ControllerRawOutput.maxByteCount })
  else { return nil }
  return parsed
}

/// Returns the integer property `key` of `dev`, or 0 when it has none.
func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Int ?? 0
}

/// Returns the string property `key` of `dev`, or nil when it has none.
func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? String
}

/// Returns the data property `key` of `dev`, or nil when it has none.
func dataProp(_ dev: IOHIDDevice, _ key: String) -> Data? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Data
}

/// Returns `count` bytes at `bytes` as lowercase hex pairs separated by spaces.
func hexString(_ bytes: UnsafePointer<UInt8>?, count: Int) -> String {
  guard let base = unsafe bytes, count > 0 else { return "" }
  return (0..<count).map { unsafe String(format: "%02x", base[$0]) }.joined(separator: " ")
}

/// Whether `first` sorts before `second` by vendor ID, then by product ID.
private func precedesByVendorAndProduct(_ first: IOHIDDevice, _ second: IOHIDDevice) -> Bool {
  let firstKey =
    intProp(first, kIOHIDVendorIDKey as String) * 0x1_0000
    + intProp(first, kIOHIDProductIDKey as String)
  let secondKey =
    intProp(second, kIOHIDVendorIDKey as String) * 0x1_0000
    + intProp(second, kIOHIDProductIDKey as String)
  return firstKey < secondKey
}

/// Returns the HID devices that match `matching`, or every device when it is nil.
func enumerateDevices(matching: [String: Any]?) -> [IOHIDDevice] {
  let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  if let matching {
    IOHIDManagerSetDeviceMatching(
      mgr,
      AppleGameControllerSyntheticHID.ioHIDMatchingExcludingSynthetics(matching) as CFDictionary
    )
  } else {
    IOHIDManagerSetDeviceMatching(
      mgr,
      AppleGameControllerSyntheticHID.allHIDDevicesExcludingSynthetics as CFDictionary
    )
  }
  _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
  defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
  return Array(
    ((IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []).sorted(
      by: precedesByVendorAndProduct
    )
  )
}

/// Returns the devices of `mgr`.
func managerDevices(_ mgr: IOHIDManager) -> [IOHIDDevice] {
  guard let rawDevices = IOHIDManagerCopyDevices(mgr) else { return [] }
  let count = CFSetGetCount(rawDevices)
  guard count > 0 else { return [] }
  let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
  defer { unsafe values.deallocate() }
  unsafe CFSetGetValues(rawDevices, values)
  return (0..<count).compactMap { idx in
    guard let value = unsafe values[idx] else { return nil }
    return unsafe unsafeBitCast(value, to: IOHIDDevice.self)
  }.sorted(by: precedesByVendorAndProduct)
}

/// Returns the input elements of `dev`.
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

/// Prints the HID devices of the same vendor and the raw USB command to try when no device matches
/// `vid` and `pid`.
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

/// Prints the usage on standard error and exits with `code`.
func printUsageAndExit(_ code: Int32) -> Never {
  unsafe fputs(
    """
    OpenJoystickDriverHIDTool. Internal hardware diagnostic utility.

    Use `just diagnose-*` for supported workflows. Run this utility directly
    only for focused hardware debugging.

    Usage:
      OpenJoystickDriverHIDTool --list
      OpenJoystickDriverHIDTool --dump --vid 0x1209 --pid 0x4a4f
      OpenJoystickDriverHIDTool --dump-elements --vid 0x1209 --pid 0x4a4f
      OpenJoystickDriverHIDTool --open --vid 0x1209 --pid 0x4a4f [--service-open] [--set-report]
      OpenJoystickDriverHIDTool --monitor [--vid <int> --pid <int>] [--seconds 10]
      OpenJoystickDriverHIDTool --usb-monitor --vid 0x1209
        [--endpoint 0x81] [--length 64] [--seconds 20]
        [--out-endpoint 0x02 --send "05 20 00 01 00; 0A 20 00 03 00 01 14"]
      OpenJoystickDriverHIDTool --record-probe <record.plist>
        [--seconds 30] [--validate-only]
      OpenJoystickDriverHIDTool --usb-passive --vid 0x3537 --pid 0x1010

    Options:
      --list           List HID devices (vid/pid/product/transport + report sizes).
      --dump           Dump the report descriptor for one device (as hex and Swift [UInt8]).
      --dump-elements  Print the input elements (usage page, usage, cookie, logical range, arrival
        order) of one device as JSON, the input of an SDL_GameControllerDB mapping.
      --open           Directly call IOHIDDeviceOpen on matching devices.
      --service-open   With --open, recreate the device from IOHIDDeviceGetService first.
      --set-report     With --open, send one Xbox 360-style rumble output report.
      --monitor        Open matching HID devices and print input value/report callbacks.
        Without ids it watches the Generic persona (from its VirtualDevice record).
      --usb-monitor    Open one raw USB service and print interrupt IN packets.
      --record-probe  Validate and exercise one controller record through the USB facade.
      --validate-only  Validate --record-probe input without opening physical hardware.
      --usb-passive    Print one authorized device's USB descriptor facts as JSON without
        opening it.
      --vid <int>      Vendor ID (decimal or 0x... hex).
      --pid <int>      Product ID (decimal or 0x... hex).
      --endpoint <n>   Interrupt IN endpoint for --usb-monitor; omitted sweeps 0x81...0x8f.
      --length <n>     Read length for --usb-monitor (default: 64, max: 1024).
      --send <bytes>   Packets --usb-monitor writes before it reads: hex pairs, packets
        separated by ';', 50 ms apart. A wedged GIP pad answers "05 20 00 01 07" by rebooting.
      --out-endpoint <n>  Interrupt OUT endpoint for --send (0x01...0x0f).
      --seconds <int>  Monitor duration in seconds (default varies, max: 300).
      -h, --help       Show this help.

    """,
    stderr
  )
  exit(code)
}
