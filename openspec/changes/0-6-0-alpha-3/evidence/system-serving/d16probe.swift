// d16probe <seconds>
// Logs, against one clock, each HID game pad that arrives or leaves and each controller
// GameController connects or disconnects, with background events on, from a process
// that is not frontmost.
import Foundation
import GameController
import IOKit.hid

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let start = Date()

func log(_ text: String) {
  print(String(format: "%8.3f", Date().timeIntervalSince(start)) + " " + text)
  fflush(stdout)
}

func prop(_ device: IOHIDDevice, _ key: String) -> Any? {
  IOHIDDeviceGetProperty(device, key as CFString)
}

func describe(_ device: IOHIDDevice) -> String {
  let vid = (prop(device, kIOHIDVendorIDKey) as? Int) ?? 0
  let pid = (prop(device, kIOHIDProductIDKey) as? Int) ?? 0
  let name = (prop(device, kIOHIDProductKey) as? String) ?? "?"
  let transport = (prop(device, kIOHIDTransportKey) as? String) ?? "?"
  let location = (prop(device, kIOHIDLocationIDKey) as? Int) ?? 0
  return String(format: "%04X:%04X", vid, pid)
    + " product=\"\(name)\" transport=\(transport) location=0x\(String(location, radix: 16))"
    + " supportsHIDDevice=\(GCController.supportsHIDDevice(device))"
}

func describe(_ controller: GCController) -> String {
  "vendorName=\"\(controller.vendorName ?? "nil")\""
    + " productCategory=\"\(controller.productCategory)\""
    + " extended=\(controller.extendedGamepad != nil) attached=\(controller.isAttachedToDevice)"
}

func logController(_ event: String, _ note: Notification) {
  guard let controller = note.object as? GCController else { return }
  log("\(event) \(describe(controller))")
}

GCController.shouldMonitorBackgroundEvents = true
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let usages: [[String: Int]] = [4, 5, 8].map {
  [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0]
}
IOHIDManagerSetDeviceMatchingMultiple(manager, usages as CFArray)
IOHIDManagerRegisterDeviceMatchingCallback(
  manager,
  { _, _, _, device in log("hid arrive  \(describe(device))") },
  nil
)
IOHIDManagerRegisterDeviceRemovalCallback(
  manager,
  { _, _, _, device in log("hid leave   \(describe(device))") },
  nil
)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

let center = NotificationCenter.default
let observers = [
  center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) {
    logController("gc connect   ", $0)
  },
  center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) {
    logController("gc disconnect", $0)
  },
]
log("pid=\(getpid()) listening \(Int(seconds))s")
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
  let listed = GCController.controllers()
  log("gc controllers() = \(listed.count): " + listed.map(describe).joined(separator: " | "))
}
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
  log("gc controllers() = \(GCController.controllers().count) at end")
  observers.forEach(center.removeObserver)
  exit(0)
}
RunLoop.main.run()
