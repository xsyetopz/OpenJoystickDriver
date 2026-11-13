import Foundation
import IOKit
import IOUSBHost

// usage, as root: usbout VVVV PPPP
// deviceCapture detaches macOS's HID driver, so the transfers reach interrupt OUT 0x05 directly.
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
  options: [.deviceCapture],
  queue: nil,
  interestHandler: nil
)
try device.__configure(withValue: 1, matchInterfaces: false)

var iterator: io_iterator_t = 0
IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator)
var interfaceService: io_service_t = 0
while case let child = IOIteratorNext(iterator), child != 0 {
  if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 { interfaceService = child }
}
let interface = try IOUSBHostInterface(
  __ioService: interfaceService,
  options: [],
  queue: nil,
  interestHandler: nil
)
let pipe = try interface.copyPipe(withAddress: 0x05)

func send(_ hex: String) {
  let bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
  let data = NSMutableData(bytes: bytes, length: bytes.count)
  var sent: UInt = 0
  do {
    try pipe.__sendIORequest(with: data, bytesTransferred: &sent, completionTimeout: 0)
    print("ep05 len=\(bytes.count) sent=\(sent) [\(hex.prefix(26))]")
  } catch {
    print("ep05 len=\(bytes.count) error=\(error)")
  }
}

func say(_ word: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
  process.arguments = [word]
  try? process.run()
  process.waitUntilExit()
}

let zeros60 = Array(repeating: "00", count: 60).joined(separator: " ")
let patterns: [(start: String, stop: String)] = [
  ("01 05 ff ff 00 00 00 00 00", "01 00 00 00 00 00 00 00 00"),
  ("01 00 08 00 ff ff 00 00 00", "01 00 00 00 00 00 00 00 00"),
  ("01 ff ff ff ff ff ff ff ff", "01 00 00 00 00 00 00 00 00"),
  ("05 ff ff 00 00", "05 00 00 00 00"),
  ("81 05 ff ff \(zeros60)", "81 00 00 00 \(zeros60)"),
  ("00 08 00 ff ff 00 00 00", "00 08 00 00 00 00 00 00"),
]
let words = ["one", "two", "three", "four", "five", "six"]
for (index, pattern) in patterns.enumerated() {
  say(words[index])
  print("#\(index + 1) \(Date())")
  send(pattern.start)
  Thread.sleep(forTimeInterval: 4)
  send(pattern.stop)
  Thread.sleep(forTimeInterval: 3)
}
say("done")
interface.destroy()
device.destroy()
