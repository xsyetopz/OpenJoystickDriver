import Foundation
import IOKit
import IOUSBHost

// usage: usbdesc VVVV PPPP
let args = CommandLine.arguments
guard args.count == 3, let vendor = Int(args[1], radix: 16),
  let product = Int(args[2], radix: 16)
else { exit(64) }
let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
matching["idVendor"] = vendor
matching["idProduct"] = product
let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
let device = try IOUSBHostDevice(
  __ioService: service,
  options: [],
  queue: nil,
  interestHandler: nil
)
guard let config = device.configurationDescriptor else { exit(1) }
let base = UnsafeRawPointer(config)
var offset = 0
while offset < Int(config.pointee.wTotalLength) {
  let length = Int(unsafe base.load(fromByteOffset: offset, as: UInt8.self))
  let bytes = (0..<length).map {
    String(format: "%02x", unsafe base.load(fromByteOffset: offset + $0, as: UInt8.self))
  }
  print(bytes.joined(separator: " "))
  offset += max(length, 1)
}
device.destroy()
