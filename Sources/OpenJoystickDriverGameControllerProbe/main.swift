import CoreHaptics
import Foundation
import GameController
import IOKit
import IOKit.hid

func hasArg(_ name: String) -> Bool {
  CommandLine.arguments.dropFirst().contains(name)
}

func argValue(_ name: String, default defaultValue: Int) -> Int {
  let args = Array(CommandLine.arguments.dropFirst())
  guard let idx = args.firstIndex(of: name), idx + 1 < args.count,
    let value = Int(args[idx + 1])
  else {
    return defaultValue
  }
  return value
}

func describe(_ controller: GCController) -> String {
  let vendor = controller.vendorName ?? "(unknown)"
  let productCategory = controller.productCategory
  let hasExtended = controller.extendedGamepad != nil
  let hasMicro = controller.microGamepad != nil
  let haptics = controllerHapticsDescription(controller)
  return "vendor=\"\(vendor)\" category=\"\(productCategory)\""
    + " extended=\(hasExtended) micro=\(hasMicro) \(haptics)"
}

func controllerHapticsDescription(_ controller: GCController) -> String {
  if #available(macOS 11.0, *) {
    guard let haptics = controller.haptics else { return "haptics=false" }
    let localities = haptics.supportedLocalities
      .map(\.rawValue)
      .sorted()
      .joined(separator: ",")
    return "haptics=true localities=[\(localities)]"
  }
  return "haptics=unavailable"
}

func playHapticPulse(on controller: GCController) -> String {
  guard #available(macOS 11.0, *) else { return "unavailable: macOS 11 required" }
  guard let haptics = controller.haptics else { return "unavailable: controller has no haptics" }
  guard let engine = haptics.createEngine(withLocality: .default) else {
    return "unavailable: no default haptic engine"
  }
  do {
    try engine.start()
    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [intensity, sharpness],
      relativeTime: 0,
      duration: 0.5
    )
    let pattern = try CHHapticPattern(events: [event], parameters: [])
    let player = try engine.makePlayer(with: pattern)
    try player.start(atTime: 0)
    Thread.sleep(forTimeInterval: 0.7)
    engine.stop()
    return "played"
  } catch {
    return "failed: \(error)"
  }
}

func installInputLogging(on controller: GCController) {
  guard let gamepad = controller.extendedGamepad else { return }

  gamepad.valueChangedHandler = { gamepad, _ in
    print(
      String(
        format:
          "GC_INPUT a=%d b=%d x=%d y=%d lb=%d rb=%d lt=%.3f rt=%.3f "
            + "lx=%.3f ly=%.3f rx=%.3f ry=%.3f dpad=(%.3f,%.3f)",
        gamepad.buttonA.isPressed ? 1 : 0,
        gamepad.buttonB.isPressed ? 1 : 0,
        gamepad.buttonX.isPressed ? 1 : 0,
        gamepad.buttonY.isPressed ? 1 : 0,
        gamepad.leftShoulder.isPressed ? 1 : 0,
        gamepad.rightShoulder.isPressed ? 1 : 0,
        gamepad.leftTrigger.value,
        gamepad.rightTrigger.value,
        gamepad.leftThumbstick.xAxis.value,
        gamepad.leftThumbstick.yAxis.value,
        gamepad.rightThumbstick.xAxis.value,
        gamepad.rightThumbstick.yAxis.value,
        gamepad.dpad.xAxis.value,
        gamepad.dpad.yAxis.value
      )
    )
  }
}

func runInstalledSelfTest(seconds: Int) -> String {
  let process = Process()
  process.executableURL = URL(
    fileURLWithPath: "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  )
  process.arguments = ["--headless", "selftest", "\(max(1, seconds))"]

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe

  do {
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  } catch {
    return "ERROR: \(error)"
  }
}

func summarizeSelfTest(_ output: String) -> [String] {
  output
    .split(separator: "\n")
    .map(String.init)
    .filter {
      $0.contains("User-space:")
        || $0.contains("DriverKit:")
        || $0.contains("ERROR:")
        || $0.contains("XPCClient")
    }
    .map { line in
      if line.contains("User-space:") {
        return "GC_SELFTEST " + line.trimmingCharacters(in: .whitespaces)
      }
      if line.contains("DriverKit:") {
        return "GC_SELFTEST " + line.trimmingCharacters(in: .whitespaces)
      }
      return "GC_SELFTEST " + line
    }
}

func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
}

func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(device, key as CFString) as? String
}

func looksLikeGamepad(_ device: IOHIDDevice) -> Bool {
  if intProp(device, kIOHIDPrimaryUsagePageKey) == kHIDPage_GenericDesktop,
    intProp(device, kIOHIDPrimaryUsageKey) == kHIDUsage_GD_GamePad
  {
    return true
  }
  let rawPairs = IOHIDDeviceGetProperty(
    device,
    kIOHIDDeviceUsagePairsKey as CFString
  )
  guard let pairs = rawPairs as? [[String: Any]]
  else {
    return false
  }
  return pairs.contains { pair in
    let page = pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0
    let usage = pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
    return page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_GamePad
  }
}

func printHIDSupport() {
  let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  IOHIDManagerSetDeviceMatching(manager, nil)
  IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  let devices = ((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [])
    .filter(looksLikeGamepad)
    .sorted {
      let leftVID = intProp($0, kIOHIDVendorIDKey)
      let rightVID = intProp($1, kIOHIDVendorIDKey)
      if leftVID != rightVID { return leftVID < rightVID }
      return intProp($0, kIOHIDProductIDKey) < intProp($1, kIOHIDProductIDKey)
    }

  print("HID GamePad support:")
  if devices.isEmpty {
    print("- none")
  }
  for device in devices {
    let vid = intProp(device, kIOHIDVendorIDKey)
    let pid = intProp(device, kIOHIDProductIDKey)
    let product = strProp(device, kIOHIDProductKey) ?? "(unknown)"
    let transport = strProp(device, kIOHIDTransportKey) ?? "(unknown)"
    let supported: String
    if #available(macOS 11.0, *) {
      supported = GCController.supportsHIDDevice(device) ? "yes" : "no"
    } else {
      supported = "unavailable"
    }
    print(
      String(
        format: "- %04X:%04X \"%@\" transport=%@ gamecontroller=%@",
        vid,
        pid,
        product,
        transport,
        supported
      )
    )
  }
  IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
}

let seconds = argValue("--seconds", default: 5)
let shouldRumble = hasArg("--rumble")
let shouldInjectSelfTest = hasArg("--inject-selftest")
let injectDelayMs = argValue("--inject-delay-ms", default: 1500)
let injectSeconds = argValue("--inject-seconds", default: 2)

print("GameController probe")
print("Listening for \(seconds)s")
if shouldRumble {
  print("Rumble pulse requested")
}
if shouldInjectSelfTest {
  print("Synthetic self-test injection requested")
}
print("")
if #available(macOS 11.3, *) {
  GCController.shouldMonitorBackgroundEvents = true
}
printHIDSupport()
print("")

let center = NotificationCenter.default
var observerTokens: [NSObjectProtocol] = []
observerTokens.append(
  center.addObserver(
    forName: .GCControllerDidConnect,
    object: nil,
    queue: .main
  ) { note in
    guard let controller = note.object as? GCController else { return }
    installInputLogging(on: controller)
    print("connect: \(describe(controller))")
  }
)
observerTokens.append(
  center.addObserver(
    forName: .GCControllerDidDisconnect,
    object: nil,
    queue: .main
  ) { note in
    guard let controller = note.object as? GCController else { return }
    print("disconnect: \(describe(controller))")
  }
)

let controllers = GCController.controllers()
print("Initial controllers: \(controllers.count)")
for controller in controllers {
  installInputLogging(on: controller)
  print("- \(describe(controller))")
}

if shouldInjectSelfTest {
  Task {
    try? await Task.sleep(nanoseconds: UInt64(max(0, injectDelayMs)) * 1_000_000)
    let output = runInstalledSelfTest(seconds: injectSeconds)
    let lines = summarizeSelfTest(output)
    if lines.isEmpty {
      print("GC_SELFTEST no summary output")
    } else {
      for line in lines {
        print(line)
      }
    }
  }
}

let end = Date().addingTimeInterval(TimeInterval(seconds))
while Date() < end {
  RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

for token in observerTokens {
  center.removeObserver(token)
}

if shouldRumble {
  let controllers = GCController.controllers()
  guard let controller = controllers.first else {
    print("rumble: skipped no controller")
    exit(1)
  }
  print("rumble: \(playHapticPulse(on: controller))")
}
