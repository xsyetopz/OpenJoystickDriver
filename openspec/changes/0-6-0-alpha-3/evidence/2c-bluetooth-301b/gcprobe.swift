import CoreHaptics
import Foundation
import GameController

// usage: gcprobe <seconds> [--rumble]
// Prints each controller the GameController framework lists and each change of its state.
let args = CommandLine.arguments
let seconds = Double(args.dropFirst().first ?? "3") ?? 3
let rumble = args.contains("--rumble")
setvbuf(stdout, nil, _IOLBF, 0)
GCController.shouldMonitorBackgroundEvents = true

let start = Date()
var engines: [CHHapticEngine] = []
var players: [CHHapticPatternPlayer] = []
var lastState: [ObjectIdentifier: String] = [:]

func stamp() -> String { String(format: "%.3f", Date().timeIntervalSince(start)) }

func state(_ pad: GCExtendedGamepad) -> String {
  let pressed = pad.allButtons.filter(\.isPressed).compactMap {
    $0.localizedName ?? $0.sfSymbolsName
  }.sorted()
  return String(
    format: "buttons=%@ dpad=(%.0f,%.0f) LS=(%.1f,%.1f) RS=(%.1f,%.1f) LT=%.1f RT=%.1f",
    pressed.description,
    pad.dpad.xAxis.value,
    pad.dpad.yAxis.value,
    pad.leftThumbstick.xAxis.value,
    pad.leftThumbstick.yAxis.value,
    pad.rightThumbstick.xAxis.value,
    pad.rightThumbstick.yAxis.value,
    pad.leftTrigger.value,
    pad.rightTrigger.value
  )
}

func describe(_ controller: GCController) {
  let localities = controller.haptics?.supportedLocalities.map(\.rawValue).sorted() ?? []
  print(
    "\(stamp()) controller vendorName=\(controller.vendorName ?? "nil") "
      + "productCategory=\(controller.productCategory) "
      + "extended=\(controller.extendedGamepad != nil) "
      + "battery=\(controller.battery?.batteryLevel.description ?? "nil") "
      + "hapticLocalities=\(localities)"
  )
  guard rumble, let engine = controller.haptics?.createEngine(withLocality: .default) else {
    return
  }
  do {
    try engine.start()
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)],
      relativeTime: 0,
      duration: 1.5
    )
    let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
    try player.start(atTime: CHHapticTimeImmediate)
    engines.append(engine)
    players.append(player)
    print("\(stamp()) haptic started on \(controller.vendorName ?? "nil")")
  } catch {
    print("\(stamp()) haptic failed on \(controller.vendorName ?? "nil"): \(error)")
  }
}

let connectObserver = NotificationCenter.default.addObserver(
  forName: .GCControllerDidConnect,
  object: nil,
  queue: .main
) { note in
  if let controller = note.object as? GCController { describe(controller) }
}
withExtendedLifetime(connectObserver) {}

let poll = Timer(timeInterval: 0.05, repeats: true) { _ in
  for controller in GCController.controllers() {
    guard let pad = controller.extendedGamepad else { continue }
    let line = state(pad)
    let key = ObjectIdentifier(controller)
    guard lastState[key] != line else { continue }
    lastState[key] = line
    print("\(stamp()) \(controller.vendorName ?? "nil"): \(line)")
  }
}
RunLoop.main.add(poll, forMode: .default)
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
print("\(stamp()) end, controllers listed: \(GCController.controllers().count)")
