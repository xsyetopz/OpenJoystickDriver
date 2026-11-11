/// How a consumer reads one persona's virtual gamepad: its SDL mapping and its W3C description.
///
/// Nothing here is written per persona. Each control is driven alone through the persona's own
/// report codec, the HID fields its input reports change are read from the persona's descriptor,
/// and SDL's macOS IOKit order names them: buttons (`bN`) are the Button and Consumer pages and
/// the Generic Desktop D-pad, Start, Select and System Main Menu usages, axes (`aN`) are Generic
/// Desktop X to Rz, Slider, Dial and Wheel and Simulation Rudder, Throttle, Accelerator and
/// Brake, each ordered by usage and then by descriptor order, and the hat is `h0.<mask>`. A
/// control the report cannot carry, or one SDL has no name for, is listed in ``unmapped``. An
/// axis whose report value falls as the control rises is bound inverted (`aN~`); a trigger binds
/// the positive half (`+aN`).
public struct VirtualGamepadMapping: Equatable, Sendable {
  /// One control driven alone, and the descriptor fields its report changed.
  public struct Probe: Equatable, Sendable {
    /// The control that was driven.
    public let control: Control
    /// The changed fields as `usagePage:usage`.
    public let fields: [String]
    /// How the report binds the control: `bN`, `aN`, `aN~` when the axis runs opposite to the
    /// control, or `h0.<mask>`; nil when the report carries the control nowhere.
    public let binding: String?
  }

  /// One entry of the W3C standard layout: its index and the device input that supplies it.
  public struct W3CEntry: Equatable, Sendable {
    /// The index in the W3C standard layout.
    public let index: Int
    /// The control at that index.
    public let control: Control
    /// The same `bN`, `aN`, `aN~` or `h0.<mask>` binding the SDL mapping uses.
    public let source: String
  }

  /// The persona the mapping describes.
  public let profile: VirtualHIDProfileID
  /// The product name of the persona.
  public let name: String
  /// The SDL3 macOS GUID, with a zero CRC.
  public let guid: String
  /// Whether SDL recognizes the persona with its default hints, from the persona's definition.
  public let worksWithDefaultSDLHints: Bool
  /// The probe of each control the persona can represent.
  public let probes: [Probe]
  /// The controls with no SDL binding, sorted by name.
  public let unmapped: [Control]
  /// The one-line SDL mapping, ending in a comma.
  public let sdlMapping: String
  /// The browser id: product name, vendor and product.
  public let w3cID: String
  /// The standard layout's buttons, ascending by index.
  ///
  /// A trigger is a button whose source is an axis.
  public let w3cButtons: [W3CEntry]
  /// The standard layout's axes, ascending by index.
  public let w3cAxes: [W3CEntry]
}

/// Why a mapping cannot be built.
public enum VirtualGamepadMappingError: Error, Equatable, Sendable {
  /// The descriptor of the persona does not parse.
  case descriptorNotParsable(VirtualHIDProfileID)
}

/// What SDL and the W3C Gamepad API call one control.
///
/// A control absent here has no SDL name.
struct ControlNames {
  /// The name in an SDL mapping.
  let sdl: String
  /// The index among the W3C standard buttons; nil when the control has none.
  let w3cButton: Int?
  /// The index among the W3C standard axes; nil when the control has none.
  let w3cAxis: Int?

  /// The names by control.
  static let table: [Control: Self] = [
    .south: .init(sdl: "a", w3cButton: 0, w3cAxis: nil),
    .east: .init(sdl: "b", w3cButton: 1, w3cAxis: nil),
    .west: .init(sdl: "x", w3cButton: 2, w3cAxis: nil),
    .north: .init(sdl: "y", w3cButton: 3, w3cAxis: nil),
    .leftShoulder: .init(sdl: "leftshoulder", w3cButton: 4, w3cAxis: nil),
    .rightShoulder: .init(sdl: "rightshoulder", w3cButton: 5, w3cAxis: nil),
    .leftTrigger: .init(sdl: "lefttrigger", w3cButton: 6, w3cAxis: nil),
    .rightTrigger: .init(sdl: "righttrigger", w3cButton: 7, w3cAxis: nil),
    .back: .init(sdl: "back", w3cButton: 8, w3cAxis: nil),
    .start: .init(sdl: "start", w3cButton: 9, w3cAxis: nil),
    .leftStickClick: .init(sdl: "leftstick", w3cButton: 10, w3cAxis: nil),
    .rightStickClick: .init(sdl: "rightstick", w3cButton: 11, w3cAxis: nil),
    .dpadUp: .init(sdl: "dpup", w3cButton: 12, w3cAxis: nil),
    .dpadDown: .init(sdl: "dpdown", w3cButton: 13, w3cAxis: nil),
    .dpadLeft: .init(sdl: "dpleft", w3cButton: 14, w3cAxis: nil),
    .dpadRight: .init(sdl: "dpright", w3cButton: 15, w3cAxis: nil),
    .guide: .init(sdl: "guide", w3cButton: 16, w3cAxis: nil),
    .capture: .init(sdl: "misc1", w3cButton: nil, w3cAxis: nil),
    .rightPaddle1: .init(sdl: "paddle1", w3cButton: nil, w3cAxis: nil),
    .leftPaddle1: .init(sdl: "paddle2", w3cButton: nil, w3cAxis: nil),
    .rightPaddle2: .init(sdl: "paddle3", w3cButton: nil, w3cAxis: nil),
    .leftPaddle2: .init(sdl: "paddle4", w3cButton: nil, w3cAxis: nil),
    .touchpadClick: .init(sdl: "touchpad", w3cButton: nil, w3cAxis: nil),
    .leftStickX: .init(sdl: "leftx", w3cButton: nil, w3cAxis: 0),
    .leftStickY: .init(sdl: "lefty", w3cButton: nil, w3cAxis: 1),
    .rightStickX: .init(sdl: "rightx", w3cButton: nil, w3cAxis: 2),
    .rightStickY: .init(sdl: "righty", w3cButton: nil, w3cAxis: 3),
  ]

  /// SDL's canonical field order in a mapping string.
  static let sdlFieldOrder = [
    "a", "b", "x", "y", "back", "guide", "start", "leftstick", "rightstick", "leftshoulder",
    "rightshoulder", "dpup", "dpdown", "dpleft", "dpright", "misc1", "paddle1", "paddle2",
    "paddle3", "paddle4", "touchpad", "leftx", "lefty", "rightx", "righty", "lefttrigger",
    "righttrigger",
  ]
}

extension VirtualHIDProfileID {
  /// The SDL mapping and W3C description of this persona.
  ///
  /// Each control the persona can represent is driven alone through the report codec, and the HID
  /// fields that its input reports change give the binding.
  ///
  /// - Throws: ``VirtualGamepadMappingError/descriptorNotParsable(_:)`` when the descriptor does
  ///   not parse.
  public func gamepadMapping() throws -> VirtualGamepadMapping {
    let profile = makeProfile()
    guard let parsed = HIDReportDescriptorParser.parse(descriptor: profile.descriptor) else {
      throw VirtualGamepadMappingError.descriptorNotParsable(self)
    }
    let numbered = parsed.inputReportIDs != [0]
    let fields = Array(parsed.fields.enumerated())
    func sdlOrder(_ isElement: (HIDField) -> Bool) -> [Int] {
      fields.filter { isElement($0.element) }
        .sorted { ($0.element.usage, $0.offset) < ($1.element.usage, $1.offset) }.map(\.offset)
    }
    let buttons = sdlOrder {
      $0.usagePage == 9 || $0.usagePage == 0x0C
        || ($0.usagePage == 1 && Self.sdlDesktopButtonUsages.contains($0.usage))
    }
    let axes = sdlOrder {
      ($0.usagePage == 1 && Self.sdlDesktopAxisUsages.contains($0.usage))
        || ($0.usagePage == 2 && Self.sdlSimulationAxisUsages.contains($0.usage))
    }
    let neutral = Self.reportsByID(profile.inputReports(for: .neutral), numbered: numbered)
    var probes: [VirtualGamepadMapping.Probe] = []
    for (control, state) in Self.probeStates(for: representableControls) {
      let reports = Self.reportsByID(profile.inputReports(for: state), numbered: numbered)
      let changed = fields.filter {
        Self.value(of: $0.element, in: reports) != Self.value(of: $0.element, in: neutral)
      }
      let changedOffsets = Set(changed.map(\.offset))
      var binding: String?
      if let index = buttons.firstIndex(where: changedOffsets.contains) {
        binding = "b\(index)"
      } else if let index = axes.firstIndex(where: changedOffsets.contains) {
        let axis = parsed.fields[axes[index]]
        let inverted =
          Self.signedValue(of: axis, in: reports) < Self.signedValue(of: axis, in: neutral)
        binding = "a\(index)" + (inverted ? "~" : "")
      } else if let hat = changed.first(where: {
        $0.element.usagePage == 1 && $0.element.usage == 0x39
      })?.element {
        let mask = [1: 1, 2: 3, 3: 2, 4: 6, 5: 4, 6: 12, 7: 8, 8: 9]
        let raw = Self.value(of: hat, in: reports) - hat.logicalMin + 1
        binding = "h0.\(mask[raw] ?? 0)"
      }
      probes.append(
        .init(
          control: control,
          fields: changed.map { "\($0.element.usagePage):\($0.element.usage)" },
          binding: binding
        )
      )
    }
    return Self.assemble(self, identity: profile.identity, probes: probes)
  }

  /// Builds the mapping from the probes: the SDL line with the bindings in SDL's field order, the
  /// W3C entries, and the controls with no binding.
  private static func assemble(
    _ id: VirtualHIDProfileID,
    identity: VirtualDeviceProfile,
    probes: [VirtualGamepadMapping.Probe]
  ) -> VirtualGamepadMapping {
    let guid = Self.guid(identity)
    var entries: [(name: String, text: String)] = []
    var unmapped: [Control] = []
    var buttons: [VirtualGamepadMapping.W3CEntry] = []
    var axes: [VirtualGamepadMapping.W3CEntry] = []
    for probe in probes {
      guard let binding = probe.binding, let names = ControlNames.table[probe.control] else {
        unmapped.append(probe.control)
        continue
      }
      let isTrigger = probe.control == .leftTrigger || probe.control == .rightTrigger
      let prefix = isTrigger && binding.hasPrefix("a") ? "+" : ""
      entries.append((names.sdl, "\(names.sdl):\(prefix)\(binding)"))
      if let index = names.w3cButton {
        buttons.append(.init(index: index, control: probe.control, source: binding))
      }
      if let index = names.w3cAxis {
        axes.append(.init(index: index, control: probe.control, source: binding))
      }
    }
    let order = ControlNames.sdlFieldOrder
    let bindings = entries.sorted {
      (order.firstIndex(of: $0.name) ?? order.count)
        < (order.firstIndex(of: $1.name) ?? order.count)
    }.map(\.text).joined(separator: ",")
    let vendor = String(identity.vendorID, radix: 16)
    let product = String(identity.productID, radix: 16)
    return VirtualGamepadMapping(
      profile: id,
      name: identity.productName,
      guid: guid,
      worksWithDefaultSDLHints: id.worksWithDefaultSDLHints,
      probes: probes,
      unmapped: unmapped.sorted { $0.rawValue < $1.rawValue },
      sdlMapping: "\(guid),\(identity.productName),\(bindings),platform:Mac OS X,",
      w3cID: "\(identity.productName) (Vendor: \(vendor) Product: \(product))",
      w3cButtons: buttons.sorted { $0.index < $1.index },
      w3cAxes: axes.sorted { $0.index < $1.index }
    )
  }

  /// Each control of `controls` with the state that drives it alone: digital controls by name,
  /// then sticks and triggers at full deflection, then the D-pad as hat directions.
  private static func probeStates(for controls: Set<Control>) -> [(Control, ControllerState)] {
    var result: [(Control, ControllerState)] = []
    let digital = controls.subtracting(
      Control.dpad.union([
        .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftTrigger, .rightTrigger,
      ])
    )
    for control in digital.sorted(by: { $0.rawValue < $1.rawValue }) {
      result.append((control, ControllerState(pressed: [control])))
    }
    let analog: [(Control, ControllerState)] = [
      (.leftStickX, ControllerState(leftStick: StickPosition(x: .max, y: .center))),
      (.leftStickY, ControllerState(leftStick: StickPosition(x: .center, y: .max))),
      (.rightStickX, ControllerState(rightStick: StickPosition(x: .max, y: .center))),
      (.rightStickY, ControllerState(rightStick: StickPosition(x: .center, y: .max))),
      (.leftTrigger, ControllerState(leftTrigger: .max)),
      (.rightTrigger, ControllerState(rightTrigger: .max)),
    ]
    result += analog.filter { controls.contains($0.0) }
    if !controls.isDisjoint(with: Control.dpad) {
      let hats: [(Control, HatDirection)] = [
        (.dpadUp, .north), (.dpadRight, .east), (.dpadDown, .south), (.dpadLeft, .west),
      ]
      result += hats.map { ($0.0, ControllerState(hat: $0.1)) }
    }
    return result
  }

  /// Generic Desktop usages SDL's IOKit backend counts as buttons: D-pad, Start, Select and
  /// System Main Menu.
  private static let sdlDesktopButtonUsages: Set<Int> = [0x90, 0x91, 0x92, 0x93, 0x3D, 0x3E, 0x85]
  /// Generic Desktop usages SDL's IOKit backend counts as axes: X to Rz, Slider, Dial and Wheel.
  private static let sdlDesktopAxisUsages = Set(0x30...0x38)
  /// Simulation usages SDL's IOKit backend counts as axes: Rudder, Throttle, Accelerator, Brake.
  private static let sdlSimulationAxisUsages: Set<Int> = [0xBA, 0xBB, 0xC4, 0xC5]

  /// Each report's payload by report ID: the first byte when the descriptor numbers its
  /// reports, else 0.
  private static func reportsByID(_ reports: [[UInt8]], numbered: Bool) -> [UInt8: [UInt8]] {
    Dictionary(
      reports.map { numbered ? ($0.first ?? 0, Array($0.dropFirst())) : (0, $0) }
    ) { first, _ in first }
  }

  /// The little-endian value of `field` in the payload of its report; 0 when no report has its
  /// ID.
  private static func value(of field: HIDField, in reports: [UInt8: [UInt8]]) -> Int {
    let payload = reports[field.reportID] ?? []
    var value = 0
    for bit in 0..<field.bitSize {
      let position = field.bitOffset + bit
      guard position / 8 < payload.count else { break }
      if payload[position / 8] & (1 << UInt8(position % 8)) != 0 { value |= 1 << bit }
    }
    return value
  }

  /// `value(of:in:)` read as two's complement when the field's logical minimum is below zero.
  private static func signedValue(of field: HIDField, in reports: [UInt8: [UInt8]]) -> Int {
    let raw = value(of: field, in: reports)
    guard field.logicalMin < 0, raw >= 1 << (field.bitSize - 1) else { return raw }
    return raw - (1 << field.bitSize)
  }

  /// Two bytes of `value` as four hex digits, low byte first.
  private static func hex(_ value: Int) -> String {
    let digits = String(UInt16(truncatingIfNeeded: value), radix: 16)
    let padded = String(repeating: "0", count: 4 - digits.count) + digits
    return String(padded.suffix(2)) + String(padded.prefix(2))
  }

  /// SDL3-style macOS GUID: bus, zero CRC, vendor, product, and version, each little-endian 16
  /// bits followed by two zero bytes except the leading bus and CRC.
  private static func guid(_ identity: VirtualDeviceProfile) -> String {
    let bus = identity.transport == "Bluetooth" ? "05" : "03"
    return bus + "000000" + hex(Int(identity.vendorID)) + "0000" + hex(Int(identity.productID))
      + "0000" + hex(identity.versionNumber) + "0000"
  }
}
