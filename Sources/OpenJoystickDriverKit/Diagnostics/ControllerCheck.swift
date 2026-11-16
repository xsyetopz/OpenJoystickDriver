public import Foundation

/// One thing a guided check asks the user to move.
public enum ControllerCheckControl: Hashable, Sendable {
  /// A button, a touch sensor or a D-pad direction; the D-pad reads the hat too.
  case button(Control)
  /// A trigger, read as an analog value.
  case trigger(Control)
  /// A stick; `true` is the left one.
  case stick(left: Bool)

  /// How far a stick or a trigger leaves rest before it counts as moved.
  private static let analogThreshold: Float = 0.35

  /// The name the check document uses: a `Control` raw value, or `LeftStick` or `RightStick`.
  public var id: String {
    switch self {
    case .button(let control), .trigger(let control): control.rawValue
    case .stick(let left): left ? "LeftStick" : "RightStick"
    }
  }

  /// The axes whose range a step of this control keeps, in document order.
  var axes: [Control] {
    switch self {
    case .button: []
    case .trigger(let control): [control]
    case .stick(let left): left ? [.leftStickX, .leftStickY] : [.rightStickX, .rightStickY]
    }
  }

  /// The controls a guided check asks about for a controller that declares `capabilities`, in
  /// `Control` order, one step per stick.
  ///
  /// The pointer axes and pointer tracking name no control the user can move alone, so they have
  /// no step.
  public static func steps(for capabilities: ControllerCapabilities) -> [Self] {
    var steps: [Self] = []
    for control in Control.allCases where capabilities.controls.contains(control) {
      let step: Self
      switch control {
      case .pointerX, .pointerY, .pointerTracking: continue
      case .leftTrigger, .rightTrigger: step = .trigger(control)
      case .leftStickX, .leftStickY: step = .stick(left: true)
      case .rightStickX, .rightStickY: step = .stick(left: false)
      default: step = .button(control)
      }
      if !steps.contains(step) { steps.append(step) }
    }
    return steps
  }

  /// Every control of `state` that is away from rest.
  static func active(in state: ControllerState) -> Set<Self> {
    var active = Set(
      state.pressed.map { Control.triggers.contains($0) ? Self.trigger($0) : Self.button($0) }
    )
    active.formUnion(state.hat.dpadControls.map(Self.button))
    if state.leftTrigger.normalized > analogThreshold { active.insert(.trigger(.leftTrigger)) }
    if state.rightTrigger.normalized > analogThreshold { active.insert(.trigger(.rightTrigger)) }
    for (left, stick) in [(true, state.leftStick), (false, state.rightStick)]
    where max(abs(stick.x.normalized), abs(stick.y.normalized)) > analogThreshold {
      active.insert(.stick(left: left))
    }
    return active
  }
}

extension Control {
  /// The two triggers.
  fileprivate static let triggers: Set<Control> = [.leftTrigger, .rightTrigger]
}

extension HatDirection {
  /// The D-pad controls the hat points at, two for a diagonal and none for neutral.
  var dpadControls: Set<Control> {
    switch self {
    case .neutral: []
    case .north: [.dpadUp]
    case .northEast: [.dpadUp, .dpadRight]
    case .east: [.dpadRight]
    case .southEast: [.dpadDown, .dpadRight]
    case .south: [.dpadDown]
    case .southWest: [.dpadDown, .dpadLeft]
    case .west: [.dpadLeft]
    case .northWest: [.dpadUp, .dpadLeft]
    }
  }
}

/// The result of a guided check: the support-report facts of one controller and what each control
/// did.
public struct ControllerCheck: Codable, Equatable, Sendable {
  /// What happened to one step.
  public enum Outcome: String, Codable, Sendable {
    /// The control left rest.
    case responded = "Responded"
    /// A different control left rest first; ``Step/otherControl`` names it.
    case otherControl = "OtherControl"
    /// The user skipped the step, or it timed out.
    case skipped = "Skipped"
  }

  /// The lowest and highest raw value one axis showed during the run.
  public struct Range: Codable, Equatable, Sendable {
    /// The axis, such as `LeftStickX` or `RightTrigger`.
    public let axis: String
    /// The lowest raw value seen.
    public let min: Int
    /// The highest raw value seen.
    public let max: Int
  }

  /// The result of asking for one control.
  public struct Step: Codable, Equatable, Sendable {
    /// The control asked for; see ``ControllerCheckControl/id``.
    public let control: String
    /// What happened.
    public let outcome: Outcome
    /// The control that moved instead, for ``Outcome/otherControl``.
    public let otherControl: String?
    /// The range seen of each axis of a stick or trigger step; empty for a button.
    public let ranges: [Range]
  }

  /// The controller facts of the support report.
  public let controller: SupportReport.Controller
  /// The mode `id` the controller runs; `default` for a record without a matching mode, nil for a
  /// controller with no record.
  public let modeID: String?
  /// The record layer that supplies the controller's record: `Bundled`, `Package` or `User`; nil
  /// without a record.
  public let recordSource: String?
  /// The OpenJoystickDriver version.
  public let appVersion: String
  /// The macOS version.
  public let osVersion: String
  /// One result per control, in the order asked.
  public let steps: [Step]

  /// Whether every control responded; false for a check with no step.
  public var allResponded: Bool { !steps.isEmpty && steps.allSatisfy { $0.outcome == .responded } }

  /// Builds the document of a finished run for `device`.
  ///
  /// - Parameters:
  ///   - device: The controller that was checked.
  ///   - record: The effective record of the controller's model, or nil.
  ///   - steps: The results of the run.
  ///   - appVersion: The version to record.
  ///   - osVersion: The macOS version to record.
  package init(
    device: ApplicationServiceDeviceDescription,
    record: ControllerRecord?,
    steps: [Step],
    appVersion: String = ApplicationVersion.current,
    osVersion: String = Self.currentOSVersion
  ) {
    controller = SupportReport.Controller(device)
    let binding = device.protocolBinding
    modeID = record.map { record in
      record.profile.modes.first {
        $0.physicalProtocolID == binding.protocolID && $0.physicalProtocolVariant == binding.variant
      }?.id ?? "default"
    }
    recordSource = record?.layer.rawValue
    self.appVersion = appVersion
    self.osVersion = osVersion
    self.steps = steps
  }

  /// The macOS version as `major.minor.patch`.
  package static var currentOSVersion: String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  }

  /// The document as a file holds it: the fields with `apiVersion` and `kind`, laid out as
  /// `ojd controller check --json` prints it.
  ///
  /// - Throws: The failure of ``OrderedJSONEncoder`` to encode the check.
  public func documentText() throws -> String {
    try OrderedJSONEncoder().encode(Envelope(check: self)).formatted()
  }

  private struct Envelope: Encodable {
    let check: ControllerCheck

    private enum CodingKeys: String, CodingKey { case apiVersion, kind }

    func encode(to encoder: any Encoder) throws {
      try check.encode(to: encoder)
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
      try container.encode("ControllerCheck", forKey: .kind)
    }
  }
}

/// The state machine of one guided check.
///
/// Feed it each controller state with ``observe(_:)``. It asks for ``current`` until that control
/// leaves rest, another control moves, or ``skip()`` is called. A button ends its step when it
/// leaves rest; a stick or trigger ends its step when it returns to rest, so its range holds the
/// whole movement. A control held when a step begins is ignored until it is released.
public struct ControllerCheckRun: Sendable {
  /// The controls to ask for, in order.
  public let controls: [ControllerCheckControl]
  /// The results so far, one per finished step.
  public private(set) var results: [ControllerCheck.Step] = []
  private var ignored: Set<ControllerCheckControl> = []
  private var lastActive: Set<ControllerCheckControl> = []
  private var ranges: [Control: ClosedRange<Int>] = [:]
  private var leftRest = false
  private var started = false

  /// Creates a run over `controls`.
  public init(controls: [ControllerCheckControl]) { self.controls = controls }

  /// The control being asked for; nil when every step has ended.
  public var current: ControllerCheckControl? {
    results.count < controls.count ? controls[results.count] : nil
  }

  /// Whether every step has ended.
  public var isFinished: Bool { current == nil }

  /// Reads `state` and ends the current step when it settles.
  public mutating func observe(_ state: ControllerState) {
    record(state)
    let active = ControllerCheckControl.active(in: state)
    defer { lastActive = active }
    guard started else {
      started = true
      ignored = active
      return
    }
    ignored.formIntersection(active)
    guard let current else { return }
    let fresh = active.subtracting(ignored)
    if fresh.contains(current) { leftRest = true }
    let responded = current.axes.isEmpty ? leftRest : leftRest && !active.contains(current)
    if responded {
      finish(.responded, active: active)
      return
    }
    let others = fresh.subtracting([current]).sorted { $0.id < $1.id }
    if let moved = others.first { finish(.otherControl, moved: moved, active: active) }
  }

  /// Ends the current step as skipped.
  public mutating func skip() {
    guard current != nil else { return }
    finish(.skipped, active: lastActive)
  }

  private mutating func record(_ state: ControllerState) {
    let values: [Control: Int] = [
      .leftStickX: Int(state.leftStick.x.rawValue), .leftStickY: Int(state.leftStick.y.rawValue),
      .rightStickX: Int(state.rightStick.x.rawValue),
      .rightStickY: Int(state.rightStick.y.rawValue),
      .leftTrigger: Int(state.leftTrigger.rawValue),
      .rightTrigger: Int(state.rightTrigger.rawValue),
    ]
    for (axis, value) in values {
      let seen = ranges[axis] ?? value...value
      ranges[axis] = min(seen.lowerBound, value)...max(seen.upperBound, value)
    }
  }

  private mutating func finish(
    _ outcome: ControllerCheck.Outcome,
    moved: ControllerCheckControl? = nil,
    active: Set<ControllerCheckControl>
  ) {
    guard let current else { return }
    results.append(
      ControllerCheck.Step(
        control: current.id,
        outcome: outcome,
        otherControl: moved?.id,
        ranges: current.axes.compactMap { axis in
          ranges[axis].map {
            ControllerCheck.Range(axis: axis.rawValue, min: $0.lowerBound, max: $0.upperBound)
          }
        }
      )
    )
    ignored = active
    leftRest = false
  }
}

/// The addresses and texts a check hands to GitHub.
///
/// Only short fields ride in a URL: a long one fails with `414 URI Too Long`. A check never sends
/// anything itself; the user submits the form.
public enum ControllerCheckIssue {
  /// The page that starts an issue.
  public static let newIssue = "https://github.com/xsyetopz/OpenJoystickDriver/issues/new"
  /// Where a validation goes, as the user reads it.
  public static let destination = "github.com/xsyetopz/OpenJoystickDriver"

  /// The `connection` options of both issue forms, which a prefilled value must equal.
  private static let usbCable = "USB cable"
  private static let bluetooth = "Bluetooth"
  private static let usbReceiver =
    "USB receiver (a wireless dongle; write its name in Controller name and maker)"

  /// The issue form of a controller problem, with the short fields of `check` filled.
  public static func supportURL(for check: ControllerCheck) -> URL {
    url(
      template: "controller-support.yml",
      [
        ("version", check.appVersion), ("vid-pid", vidPid(check)),
        ("connection", connection(check)), ("mode", check.modeID ?? "None"),
      ]
    )
  }

  /// The validation form with the short fields of `check` filled.
  public static func validationURL(for check: ControllerCheck) -> URL {
    let responded = check.steps.count { $0.outcome == .responded }
    return url(
      template: "controller-validation.yml",
      [
        ("version", check.appVersion), ("vid-pid", vidPid(check)),
        ("connection", connection(check)), ("mode", check.modeID ?? "None"),
        ("source", check.recordSource ?? "None"), ("macos", check.osVersion),
        ("controls", "\(responded) of \(check.steps.count)"),
      ]
    )
  }

  /// The text a validation holds, or nil unless the controller has a record and every control
  /// responded, because a validation names a mode of the record.
  ///
  /// It holds the VID:PID, mode `id`, connection, record source, versions and per-control results,
  /// and no serial number, unit ID, Bluetooth address, user name or path.
  public static func validationText(for check: ControllerCheck) -> String? {
    guard check.allResponded, let modeID = check.modeID, let source = check.recordSource else {
      return nil
    }
    var lines = [
      "VID:PID: \(vidPid(check))", "Mode: \(modeID)",
      "Connection: \(connection(check))", "Record source: \(source)",
      "OpenJoystickDriver: \(check.appVersion)", "macOS: \(check.osVersion)",
      "Controls: \(check.steps.count) of \(check.steps.count) responded",
    ]
    for step in check.steps {
      let ranges = step.ranges.map { "\($0.axis) \($0.min)...\($0.max)" }.joined(separator: ", ")
      lines.append("\(step.control): responded" + (ranges.isEmpty ? "" : " (\(ranges))"))
    }
    return lines.joined(separator: "\n")
  }

  private static func vidPid(_ check: ControllerCheck) -> String {
    unsafe String(format: "%04x:%04x", check.controller.vendorID, check.controller.productID)
  }

  private static func connection(_ check: ControllerCheck) -> String {
    if check.controller.connection == "Bluetooth" { return bluetooth }
    return check.controller.protocolBinding.hasSuffix(":Receiver") ? usbReceiver : usbCable
  }

  private static func url(template: String, _ fields: [(String, String)]) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/xsyetopz/OpenJoystickDriver/issues/new"
    components.queryItems = ([("template", template)] + fields).map(URLQueryItem.init)
    return components.url ?? URL(fileURLWithPath: "/")
  }
}
