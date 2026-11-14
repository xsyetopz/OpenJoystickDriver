import Foundation

/// The driver of a family whose record also holds `input.layouts`: the family driver runs the
/// session and decodes every report, and the layout that selects a report overrides the controls
/// it names.
///
/// A report no layout selects, and every control no selected layout names, stay the family
/// driver's.
final class LayeredInputDriver: PhysicalProtocolDriver {
  let family: any PhysicalProtocolDriver
  private let layers: ReportLayoutDriver
  /// The family driver's latest state, which a report only the layouts select starts from.
  private var lastState = ControllerState.neutral

  init(family: any PhysicalProtocolDriver, layouts: ControllerInputLayouts) {
    self.family = family
    layers = ReportLayoutDriver(layouts: layouts)
  }

  var capabilities: ControllerCapabilities {
    family.capabilities.union(ControllerCapabilities(controls: layers.layouts.controls))
  }
  var sessionPlan: DriverSessionPlan { family.sessionPlan }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let selected = layers.layouts.indexOfLayout(selecting: [UInt8](data))
    let event: ControllerEvent?
    do {
      event = try family.parse(report: data, receivedAt: receivedAt)
    } catch {
      // A report of the device's own shape is no frame of the family; its layout decodes it.
      guard selected != nil else { throw error }
      event = nil
    }
    if let event { lastState = event.state }
    guard let index = selected, let layered = layers.parse(report: data, receivedAt: receivedAt)
    else { return event }
    let layout = layers.layouts.layouts[index]
    var state = lastState
    for button in layout.buttons {
      state.set(button.control, pressed: layered.state.pressed.contains(button.control))
    }
    var sticks = [state.leftStick.x, state.leftStick.y, state.rightStick.x, state.rightStick.y]
    let layeredSticks = [
      layered.state.leftStick.x, layered.state.leftStick.y,
      layered.state.rightStick.x, layered.state.rightStick.y,
    ]
    for axis in layout.axes {
      guard let slot = Control.stickAxes.firstIndex(of: axis.control) else { continue }
      sticks[slot] = layeredSticks[slot]
    }
    state.leftStick = StickPosition(x: sticks[0], y: sticks[1])
    state.rightStick = StickPosition(x: sticks[2], y: sticks[3])
    if !layout.hat.isEmpty { state.hat = layered.state.hat }
    if layout.leftTrigger != nil { state.leftTrigger = layered.state.leftTrigger }
    if layout.rightTrigger != nil { state.rightTrigger = layered.state.rightTrigger }
    return ControllerEvent(
      timestamp: receivedAt,
      state: state,
      motion: event?.motion ?? [],
      touchFrames: event?.touchFrames ?? [],
      isFresh: event?.isFresh ?? true
    )
  }

  func parse(elementValue: HIDElementValue, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    let event = family.parse(elementValue: elementValue, receivedAt: receivedAt)
    if let event { lastState = event.state }
    return event
  }
  var latestInputReportFormat: String? { family.latestInputReportFormat }
  var power: ControllerConnectionState.Power? { family.power }
  var wiiRemoteStatus: WiiRemoteStatus? { family.wiiRemoteStatus }
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    family.consumeInputConnectionStateChange()
  }
  func resetProtocolState() {
    lastState = .neutral
    layers.resetProtocolState()
    family.resetProtocolState()
  }
  func startupWrites() -> [PhysicalOutputWrite] { family.startupWrites() }
  func activationWrites() -> [PhysicalOutputWrite] { family.activationWrites() }
  func deactivationWrites() -> [PhysicalOutputWrite] { family.deactivationWrites() }
  func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] { family.startupFeatureReads() }
  func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool {
    family.consumeFeatureReply(data, request: request)
  }
  func consumeUSBCommandReply(_ bytes: [UInt8]) { family.consumeUSBCommandReply(bytes) }
  func startupRecoveryWrites() -> [PhysicalOutputWrite] { family.startupRecoveryWrites() }
  func expireStartupRecovery() { family.expireStartupRecovery() }
  func presenceRequestWrite() -> PhysicalOutputWrite? { family.presenceRequestWrite() }
  func keepAliveWrites() -> [PhysicalOutputWrite] { family.keepAliveWrites() }
  func powerOffWrites() -> [PhysicalOutputWrite] { family.powerOffWrites() }
  func setPointerInputWanted(_ wanted: Bool) { family.setPointerInputWanted(wanted) }
  func drainPendingWrites() -> [PhysicalOutputWrite] { family.drainPendingWrites() }
  func inputConnectionWrites(for state: ControllerInputConnectionState) -> [PhysicalOutputWrite] {
    family.inputConnectionWrites(for: state)
  }
  var outputCapabilities: PhysicalControllerOutputCapabilities { family.outputCapabilities }
  var defaultColor: ControllerColor? { family.defaultColor }
  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    try family.encode(command)
  }
}
