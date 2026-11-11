import CoreHaptics
import Foundation
import GameController
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform

/// Tells whether the command line contains the flag `name`.
func hasArg(_ name: String) -> Bool { CommandLine.arguments.dropFirst().contains(name) }

/// Returns the integer that follows `name` on the command line, or `defaultValue` when there is
/// none.
func argValue(_ name: String, default defaultValue: Int) -> Int {
  let args = Array(CommandLine.arguments.dropFirst())
  guard let idx = args.firstIndex(of: name), idx + 1 < args.count, let value = Int(args[idx + 1])
  else { return defaultValue }
  return value
}

/// Returns a one-line description of the vendor, category and profiles of `controller`.
func describe(_ controller: GCController) -> String {
  let vendor = controller.vendorName ?? "(unknown)"
  let productCategory = controller.productCategory
  let hasExtended = controller.extendedGamepad != nil
  let hasMicro = controller.microGamepad != nil
  let haptics = controllerHapticsDescription(controller)
  return "vendor=\"\(vendor)\" category=\"\(productCategory)\""
    + " extended=\(hasExtended) micro=\(hasMicro) \(haptics)"
}

/// Returns the button names of `controller` and, for an Xbox gamepad, its Share button and paddle
/// count.
func describeInputs(_ controller: GCController) -> String {
  let names = controller.physicalInputProfile.buttons.keys.sorted().joined(separator: ",")
  guard let xbox = controller.extendedGamepad as? GCXboxGamepad else {
    return "buttons=[\(names)] xbox=false"
  }
  let share = xbox.buttonShare != nil
  let paddles = [xbox.paddleButton1, xbox.paddleButton2, xbox.paddleButton3, xbox.paddleButton4]
    .compactMap { $0 }.count
  return "buttons=[\(names)] xbox=true share=\(share) paddles=\(paddles)"
}

/// Returns whether `controller` has haptics and the localities it supports.
func controllerHapticsDescription(_ controller: GCController) -> String {
  guard let haptics = controller.haptics else { return "haptics=false" }
  let localities = haptics.supportedLocalities.map(\.rawValue).sorted().joined(separator: ",")
  return "haptics=true localities=[\(localities)]"
}

/// Plays a half-second haptic pulse on `controller` and returns `played`, or the reason it could
/// not.
func playHapticPulse(on controller: GCController) -> String {
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
  } catch { return "failed: \(error)" }
}

/// Returns the integer property `key` of `device`, or 0 when it has none.
func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
}

/// Returns the string property `key` of `device`, or nil when it has none.
func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(device, key as CFString) as? String
}

/// Tells whether `device` reports the Generic Desktop GamePad usage, as its primary usage or in its
/// usage pairs.
func looksLikeGamepad(_ device: IOHIDDevice) -> Bool {
  if intProp(device, kIOHIDPrimaryUsagePageKey) == kHIDPage_GenericDesktop,
    intProp(device, kIOHIDPrimaryUsageKey) == kHIDUsage_GD_GamePad
  {
    return true
  }
  let rawPairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
  guard let pairs = rawPairs as? [[String: Any]] else { return false }
  return pairs.contains { pair in
    let page = pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0
    let usage = pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
    return page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_GamePad
  }
}

/// Prints each HID gamepad and whether GameController supports it.
///
/// - Returns: Whether any listed device is supported, or nil when no gamepad is listed.
func printHIDSupport() -> Bool? {
  let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  IOHIDManagerSetDeviceMatching(
    manager,
    AppleGameControllerSyntheticHID.allHIDDevicesExcludingSynthetics as CFDictionary
  )
  IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  let devices = ((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []).filter(
    looksLikeGamepad
  ).sorted {
    let leftVID = intProp($0, kIOHIDVendorIDKey)
    let rightVID = intProp($1, kIOHIDVendorIDKey)
    if leftVID != rightVID { return leftVID < rightVID }
    return intProp($0, kIOHIDProductIDKey) < intProp($1, kIOHIDProductIDKey)
  }

  print("HID GamePad support:")
  if devices.isEmpty { print("- none") }
  var observedSupport: [Bool] = []
  for device in devices {
    let vid = intProp(device, kIOHIDVendorIDKey)
    let pid = intProp(device, kIOHIDProductIDKey)
    let product = strProp(device, kIOHIDProductKey) ?? "(unknown)"
    let transport = strProp(device, kIOHIDTransportKey) ?? "(unknown)"
    let value = GCController.supportsHIDDevice(device)
    observedSupport.append(value)
    let supported = value ? "yes" : "no"
    print(
      unsafe String(
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
  return observedSupport.isEmpty ? nil : observedSupport.contains(true)
}

/// Records what the probe observed: connection, an extended profile, input, disconnection and
/// reconnection.
final class ProbeEvidence: Sendable {
  /// The observed flags, guarded by a lock.
  private struct Values {
    /// A controller connected.
    var connected = false
    /// A connected controller has an extended gamepad profile.
    var extended = false
    /// An input value changed.
    var input = false
    /// A controller disconnected.
    var disconnected = false
    /// A controller connected after a disconnection.
    var reconnected = false
    /// A disconnection happened, so the next connection counts as a reconnection.
    var sawDisconnect = false
  }

  /// The observed flags.
  private let values = Locked(Values())

  /// Records that `controller` connected, and whether it is a reconnection or has an extended
  /// profile.
  func markConnected(_ controller: GCController) {
    let isExtended = controller.extendedGamepad != nil
    values.withLock { values in
      values.connected = true
      if values.sawDisconnect { values.reconnected = true }
      if isExtended { values.extended = true }
    }
  }

  /// Records that an input value changed.
  func markInput() { values.withLock { $0.input = true } }

  /// Records that a controller disconnected.
  func markDisconnected() {
    values.withLock { values in
      values.disconnected = true
      values.sawDisconnect = true
    }
  }

  /// Returns the flags in the order connected, extended, input, disconnected, reconnected.
  func snapshot() -> (Bool, Bool, Bool, Bool, Bool) {
    values.withLock { values in
      (values.connected, values.extended, values.input, values.disconnected, values.reconnected)
    }
  }
}

/// The seconds to listen, from `--seconds` and bounded by the probe configuration.
let seconds = GameControllerProbeConfiguration.boundedSeconds(
  argValue("--seconds", default: GameControllerProbeConfiguration.defaultSeconds)
)
/// Whether `--rumble` asks for a haptic pulse at the end.
let shouldRumble = hasArg("--rumble")
/// Whether `--disable-system-gestures` stops the system from taking the controller's Options, Home
/// and Share buttons.
let shouldDisableSystemGestures = hasArg("--disable-system-gestures")

print("GameController probe")
print("Listening for \(seconds)s")
if shouldRumble { print("Rumble pulse requested") }
if shouldDisableSystemGestures {
  print("System controller gestures disabled for this test")
  // GameController sends Home and Share only to the frontmost app, and this tool has no window.
  print(
    "Home and Share reach only the frontmost app: test them with "
      + "OpenJoystickDriverGameControllerViewer"
  )
}
print("")
GCController.shouldMonitorBackgroundEvents = true
/// Whether GameController supports any listed HID gamepad; nil when none is listed.
let supportsHID = printHIDSupport()
print("")

/// The notification center that delivers the connect and disconnect notifications.
let center = NotificationCenter.default
/// The observers to remove when the listening ends.
var observerTokens: [any NSObjectProtocol] = []
/// The controllers connected when the probe starts.
let controllers = GCController.controllers()
/// What the probe has observed.
let evidence = ProbeEvidence()

/// Records `controller` as connected and prints its button changes.
///
/// With `disableSystemGestures`, the Options, Home and Share buttons stop triggering system
/// gestures.
func observeInput(on controller: GCController, disableSystemGestures: Bool) {
  evidence.markConnected(controller)
  guard let gamepad = controller.extendedGamepad else { return }
  if disableSystemGestures {
    gamepad.buttonOptions?.preferredSystemGestureState = .disabled
    gamepad.buttonHome?.preferredSystemGestureState = .disabled
    if let xbox = gamepad as? GCXboxGamepad {
      xbox.buttonShare?.preferredSystemGestureState = .disabled
    }
  }
  gamepad.valueChangedHandler = { _, _ in evidence.markInput() }
  if #available(macOS 13.0, *) {
    controller.physicalInputProfile.valueDidChangeHandler = { _, element in
      guard let button = element as? GCControllerButtonInput else { return }
      let name = button.aliases.min() ?? button.localizedName ?? "Button"
      print("button: \(name) value=\(button.value) pressed=\(button.isPressed)")
    }
  }
}

for controller in controllers {
  observeInput(on: controller, disableSystemGestures: shouldDisableSystemGestures)
}
observerTokens.append(
  center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
    guard let controller = note.object as? GCController else { return }
    observeInput(on: controller, disableSystemGestures: shouldDisableSystemGestures)
    print("connect: \(describe(controller))")
    print("inputs: \(describeInputs(controller))")
  }
)
observerTokens.append(
  center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { note in
    guard let controller = note.object as? GCController else { return }
    evidence.markDisconnected()
    print("disconnect: \(describe(controller))")
  }
)

print("Initial controllers: \(controllers.count)")
for controller in controllers {
  print("- \(describe(controller))")
  print("  \(describeInputs(controller))")
}

/// The time when the listening ends.
let end = Date().addingTimeInterval(TimeInterval(seconds))
while Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }

for token in observerTokens { center.removeObserver(token) }

/// The observed flags at the end of the listening.
let evidenceResult = evidence.snapshot()
/// The HID support as text, `unknown` when no gamepad is listed.
let supportsHIDDescription = supportsHID.map { String($0) } ?? "unknown"
print(
  "evidence supports_hid=\(supportsHIDDescription) connect=\(evidenceResult.0) "
    + "extended_profile=\(evidenceResult.1) live_input=\(evidenceResult.2) "
    + "disconnect=\(evidenceResult.3) reconnect=\(evidenceResult.4) haptics=unclaimed"
)

if shouldRumble {
  let connected = GCController.controllers()
  guard let controller = connected.first else {
    print("rumble: skipped no controller")
    exit(1)
  }
  print("rumble: \(playHapticPulse(on: controller))")
}
