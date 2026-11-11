import Foundation
import IOKit.hid

// usage: hidset VVVV PPPP output|feature reportID hex bytes...
let args = CommandLine.arguments
guard args.count >= 5, let vendor = Int(args[1], radix: 16), let product = Int(args[2], radix: 16),
  let reportID = Int(args[4], radix: 16)
else { exit(64) }
let type = args[3] == "feature" ? kIOHIDReportTypeFeature : kIOHIDReportTypeOutput
let payload = args.dropFirst(5).compactMap { UInt8($0, radix: 16) }

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(
  manager, [kIOHIDVendorIDKey: vendor, kIOHIDProductIDKey: product] as CFDictionary)
guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
  let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
else { print("open failed"); exit(1) }
for device in devices {
  let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"
  let result = IOHIDDeviceSetReport(device, type, CFIndex(reportID), payload, payload.count)
  let hex = payload.map { String(format: "%02x", $0) }.joined(separator: " ")
  print("\(transport) \(args[3]) id=\(reportID) [\(hex)] result=\(String(UInt32(bitPattern: result), radix: 16))")
}
if let seconds = Double(ProcessInfo.processInfo.environment["HOLD"] ?? "") {
  Thread.sleep(forTimeInterval: seconds)
}
