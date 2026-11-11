import Foundation
import IOKit.hid

// usage: hidcap <vendorID> <productID> <seconds> [hex bytes of one output report, report ID first]
let args = CommandLine.arguments
guard args.count >= 4, let vendor = Int(args[1], radix: 16), let product = Int(args[2], radix: 16),
  let seconds = Double(args[3])
else {
  FileHandle.standardError.write(Data("usage: hidcap VVVV PPPP seconds [hex bytes]\n".utf8))
  exit(64)
}
let output = args.dropFirst(4).compactMap { UInt8($0, radix: 16) }
setvbuf(stdout, nil, _IOLBF, 0)

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(
  manager, [kIOHIDVendorIDKey: vendor, kIOHIDProductIDKey: product] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard opened == kIOReturnSuccess else {
  print("open failed: \(String(opened, radix: 16))")
  exit(1)
}
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first
else {
  print("no device")
  exit(1)
}

let start = Date()
var last = Data()
let size = 64
let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
IOHIDDeviceRegisterInputReportCallback(
  device, buffer, size,
  { _, _, _, _, reportID, report, length in
    let data = Data(bytes: report, count: length)
    guard data != last else { return }
    last = data
    let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
    print(String(format: "%.3f rx id=%d len=%d %@", Date().timeIntervalSince(start), reportID, length, hex))
  }, nil)

if let reportID = output.first {
  // HIDCAP_NO_ID=1 sends the payload without the report ID byte in front.
  let payload = ProcessInfo.processInfo.environment["HIDCAP_NO_ID"] == nil ? output : Array(output.dropFirst())
  let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), payload, payload.count)
  let hex = output.map { String(format: "%02x", $0) }.joined(separator: " ")
  print(String(format: "%.3f tx len=%d %@ result=%x", Date().timeIntervalSince(start), output.count, hex, result))
}
CFRunLoopRunInMode(CFRunLoopMode.defaultMode, seconds, false)
print(String(format: "%.3f end", Date().timeIntervalSince(start)))
