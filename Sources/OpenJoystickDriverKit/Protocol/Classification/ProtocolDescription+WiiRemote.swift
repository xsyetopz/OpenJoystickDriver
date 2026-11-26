import Foundation

extension ProtocolDescription {
  /// `defaults.session.wiiRemote`: the wire facts of the Wii Remote that a table can state, which
  /// are the report layouts, button and LED bits, extension ids, the register scripts and their
  /// timing.
  ///
  /// The state machine that sequences the scripts, the calibration math, the IR pointer and the
  /// speaker codec stay in the driver. Only `NintendoWii` has it.
  struct WiiRemote: Decodable, Equatable, Sendable {
    /// The bit of the first data byte of every output report that drives the motor.
    let rumbleBit: Int
    /// The output report that sets the LEDs.
    let ledReport: UInt8
    /// The bit of the first data byte of `ledReport` that lights the first LED; the next three
    /// bits light the others.
    let ledFirstBit: Int
    /// The core buttons.
    let coreButtons: [Button]
    /// The low accelerometer bits.
    let accelerometerLowBits: AccelerometerLowBits
    /// The input report modes.
    let reportModes: [ReportMode]
    /// The report-mode choice table.
    let modeChoices: [ModeChoice]
    /// The extension ids.
    let extensions: [ExtensionID]
    /// The IR sensitivity levels.
    let irSensitivityLevels: [IRSensitivityLevel]
    /// The level the driver writes when nothing chooses another.
    let defaultIRSensitivityLevel: Int
    /// The byte of each IR mode, by format.
    let irModeBytes: [BlockKind: UInt8]
    /// The Motion Plus mode byte for no extension, a Nunchuk and a Classic Controller.
    let motionPlusModeBytes: [String: UInt8]
    /// The scripts.
    let scripts: Scripts

    /// Decodes and validates the field; an unknown key, a missing key, a value outside its range,
    /// a report mode outside `0x30...0x3F`, overlapping blocks, an extension id that is not six
    /// bytes or an extension layout that reuses a bit or a control is rejected.
    init(from decoder: any Decoder) throws {
      let root = try WiiReader(
        try decoder.container(keyedBy: DocumentKey.self),
        allowed: [
          "rumbleBit", "led", "coreButtons", "accelerometerLowBits", "reportModes", "modeChoices",
          "extensions", "irSensitivity", "irModeBytes", "motionPlusModeBytes", "scripts",
        ]
      )
      rumbleBit = try root.number("rumbleBit", 0...7)
      let led = try root.object("led", allowed: ["report", "firstBit"])
      ledReport = UInt8(try led.number("report", 0x10...0x1A))
      ledFirstBit = try led.number("firstBit", 0...4)
      coreButtons = try Self.coreButtons(root)
      accelerometerLowBits = try Self.accelerometerLowBits(root)
      let modes = try Self.reportModes(root)
      reportModes = modes
      modeChoices = try Self.modeChoices(root, carriedBy: modes)
      extensions = try Self.extensionIDs(root)
      let ir = try Self.irSensitivity(root)
      irSensitivityLevels = ir.levels
      defaultIRSensitivityLevel = ir.defaultLevel
      irModeBytes = try Self.irModeBytes(root)
      motionPlusModeBytes = try Self.motionPlusModeBytes(root)
      scripts = try Self.scripts(root)
    }
  }
}

extension ProtocolDescription.WiiRemote {
  /// The core buttons, each control once.
  fileprivate static func coreButtons(_ root: WiiReader) throws -> [Button] {
    let buttons = try root.list("coreButtons", 1...16, allowed: ["control", "byte", "mask"]) {
      let name = try $0.string("control")
      guard let control = Control(rawValue: name) else {
        throw $0.fail("control", "\(name) is not a control")
      }
      return Button(control: control, field: try $0.bitField(bytes: 0...1))
    }
    guard Set(buttons.map(\.control)).count == buttons.count else {
      throw root.fail("coreButtons", "a control appears at most once")
    }
    return buttons
  }

  /// The low accelerometer bits of the three axes.
  fileprivate static func accelerometerLowBits(_ root: WiiReader) throws -> AccelerometerLowBits {
    let low = try root.object("accelerometerLowBits", allowed: ["x", "y", "z"])
    return AccelerometerLowBits(
      x: try low.object("x", allowed: ["byte", "mask"]).bitField(bytes: 0...1),
      y: try low.object("y", allowed: ["byte", "mask"]).bitField(bytes: 0...1),
      z: try low.object("z", allowed: ["byte", "mask"]).bitField(bytes: 0...1)
    )
  }

  /// The input report modes, each id once.
  fileprivate static func reportModes(_ root: WiiReader) throws -> [ReportMode] {
    let modes = try root.list("reportModes", 1...16, allowed: ["id", "blocks"]) {
      try ReportMode(reader: $0)
    }
    guard Set(modes.map(\.id)).count == modes.count else {
      throw root.fail("reportModes", "a report mode id appears at most once")
    }
    return modes
  }

  /// The report-mode choices, each naming a mode of `modes` that carries its features.
  fileprivate static func modeChoices(
    _ root: WiiReader,
    carriedBy modes: [ReportMode]
  ) throws -> [ModeChoice] {
    let choices = try root.list("modeChoices", 1...32, allowed: ["features", "mode"]) {
      let names = try $0.strings("features")
      let features = Set(names.compactMap(BlockKind.init(rawValue:)))
      guard features.count == names.count, !features.contains(.buttons) else {
        throw $0.fail("features", "features are unique blocks other than Buttons")
      }
      let mode = UInt8(
        try $0.number(
          "mode",
          Int(ReportMode.idRange.lowerBound)...Int(ReportMode.idRange.upperBound)
        )
      )
      return ModeChoice(features: features, mode: mode)
    }
    for choice in choices {
      let carried = modes.first { $0.id == choice.mode }.map { Set($0.blocks.map(\.kind)) }
      guard let carried, choice.features.isSubset(of: carried) else {
        throw root.fail("modeChoices", "a choice names a mode that carries its features")
      }
    }
    guard Set(choices.map(\.features)).count == choices.count else {
      throw root.fail("modeChoices", "a feature set appears at most once")
    }
    return choices
  }

  /// The extension ids, each kind and each id once.
  fileprivate static func extensionIDs(_ root: WiiReader) throws -> [ExtensionID] {
    let kinds = try root.list("extensions", 1...16, allowed: ["kind", "id", "layout"]) {
      ExtensionID(
        kind: try $0.string("kind"),
        id: try $0.bytes("id", 6...6),
        layout: try $0.keys.contains("layout")
          ? ExtensionLayout(reader: $0.object("layout", allowed: ExtensionLayout.keys)) : nil
      )
    }
    guard Set(kinds.map(\.kind)).count == kinds.count,
      Set(kinds.map(\.id)).count == kinds.count
    else {
      throw root.fail("extensions", "each kind and each id appears at most once")
    }
    return kinds
  }

  /// The IR sensitivity levels and the default level.
  fileprivate static func irSensitivity(
    _ root: WiiReader
  ) throws -> (levels: [IRSensitivityLevel], defaultLevel: Int) {
    let ir = try root.object("irSensitivity", allowed: ["default", "levels"])
    let levels = try ir.list("levels", 1...9, allowed: ["level", "block1", "block2"]) {
      IRSensitivityLevel(
        level: try $0.number("level", 1...9),
        block1: try $0.bytes("block1", 9...9),
        block2: try $0.bytes("block2", 2...2)
      )
    }
    let defaultLevel = try ir.number("default", 1...9)
    guard levels.map(\.level) == Array(1...levels.count), defaultLevel <= levels.count else {
      throw root.fail("irSensitivity", "levels count up from 1 and include the default")
    }
    return (levels, defaultLevel)
  }

  /// The byte of each IR mode, by format.
  fileprivate static func irModeBytes(_ root: WiiReader) throws -> [BlockKind: UInt8] {
    let formats: [(key: String, kind: BlockKind)] = [
      ("basic", .irBasic), ("extended", .irExtended), ("full", .irFull),
    ]
    let modeObject = try root.object("irModeBytes", allowed: Set(formats.map(\.key)))
    return Dictionary(
      uniqueKeysWithValues: try formats.map {
        ($0.kind, UInt8(try modeObject.number($0.key, 0...255)))
      }
    )
  }

  /// The Motion Plus mode byte for no extension, a Nunchuk and a Classic Controller.
  fileprivate static func motionPlusModeBytes(_ root: WiiReader) throws -> [String: UInt8] {
    let plusKeys = ["standalone", "nunchuk", "classic"]
    let plusObject = try root.object("motionPlusModeBytes", allowed: Set(plusKeys))
    return Dictionary(
      uniqueKeysWithValues: try plusKeys.map { ($0, UInt8(try plusObject.number($0, 0...255))) }
    )
  }

  /// The register scripts.
  fileprivate static func scripts(_ root: WiiReader) throws -> Scripts {
    let scriptObject = try root.object(
      "scripts",
      allowed: [
        "handshake", "accelerometerCalibration", "motionPlus", "ir", "irStop", "speaker",
        "speakerStop",
      ]
    )
    return Scripts(
      handshake: try Step.list(scriptObject, "handshake"),
      accelerometerCalibration: try Step.list(scriptObject, "accelerometerCalibration"),
      motionPlus: try Step.list(scriptObject, "motionPlus"),
      ir: try Step.list(scriptObject, "ir"),
      irStop: try Step.list(scriptObject, "irStop"),
      speaker: try Step.list(scriptObject, "speaker"),
      speakerStop: try Step.list(scriptObject, "speakerStop")
    )
  }
}

extension ProtocolDescription.WiiRemote.ExtensionLayout {
  /// The keys a layout sets.
  fileprivate static let keys: Set<String> = [
    "buttons", "sticks", "stickCenter", "triggers", "accelerometer",
  ]

  /// Reads a layout: contiguous masks, no bit in two fields, a control once, a stick or trigger
  /// of 1 to 8 bits, a stick half range of at most `2^bits`, an accelerometer axis of 1 to 10
  /// bits, and a center rule exactly when there are sticks.
  fileprivate init(reader: WiiReader) throws {
    typealias Wii = ProtocolDescription.WiiRemote
    var used = [UInt8](repeating: 0, count: 6)
    var controls: Set<Control> = []

    func claim(_ field: Wii.ExtensionField, _ widths: ClosedRange<Int>, key: String) throws {
      guard widths.contains(field.bits) else {
        throw reader.fail(key, "a \(key) field is \(widths.lowerBound)...\(widths.upperBound) bits")
      }
      for part in field.parts {
        guard used[part.byte] & part.mask == 0 else {
          throw reader.fail(key, "each bit of the six data bytes belongs to one field")
        }
        used[part.byte] |= part.mask
      }
    }
    func claim(_ control: Control, key: String) throws {
      guard controls.insert(control).inserted else {
        throw reader.fail(key, "a control appears at most once in a layout")
      }
    }
    func entries<Value>(
      _ key: String,
      _ count: ClosedRange<Int>,
      allowed: Set<String>,
      _ read: (WiiReader) throws -> Value
    ) throws -> [Value] {
      try reader.keys.contains(key) ? reader.list(key, count, allowed: allowed, read) : []
    }

    guard !reader.keys.isEmpty else {
      throw reader.fail("layout", "a layout sets at least one field")
    }
    buttons = try entries("buttons", 1...16, allowed: ["control", "byte", "mask", "pressedWhen"]) {
      let control = try $0.control()
      try claim(control, key: "buttons")
      let field = try $0.bitField(bytes: 0...5)
      try claim(Wii.ExtensionField(parts: [field]), 1...8, key: "buttons")
      let level = try $0.string("pressedWhen")
      guard ["Set", "Clear"].contains(level) else {
        throw $0.fail("pressedWhen", "pressedWhen is Set or Clear")
      }
      return Wii.ExtensionButton(control: control, field: field, pressedWhenSet: level == "Set")
    }
    sticks = try entries("sticks", 1...4, allowed: ["control", "parts", "halfRange"]) {
      let control = try $0.control()
      guard Control.stickAxes.contains(control) else {
        throw $0.fail("control", "a stick drives a stick axis")
      }
      try claim(control, key: "sticks")
      let field = try $0.field("parts")
      try claim(field, 1...8, key: "sticks")
      return Wii.ExtensionStick(
        control: control,
        field: field,
        halfRange: try $0.number("halfRange", 1...(1 << field.bits))
      )
    }
    stickCenter =
      try reader.keys.contains("stickCenter")
      ? Wii.StickCenter(rawValue: reader.string("stickCenter"))
        ?? {
          throw reader.fail("stickCenter", "stickCenter is FirstSample")
        }() : nil
    guard (stickCenter != nil) == !sticks.isEmpty else {
      throw reader.fail("stickCenter", "stickCenter is FirstSample exactly when there are sticks")
    }
    triggers = try entries("triggers", 1...2, allowed: ["control", "parts"]) {
      let control = try $0.control()
      guard control == .leftTrigger || control == .rightTrigger else {
        throw $0.fail("control", "a trigger drives LeftTrigger or RightTrigger")
      }
      try claim(control, key: "triggers")
      let field = try $0.field("parts")
      try claim(field, 1...8, key: "triggers")
      return Wii.ExtensionTrigger(control: control, field: field)
    }
    if reader.keys.contains("accelerometer") {
      let axes = try reader.object("accelerometer", allowed: ["x", "y", "z"])
      let fields = try ["x", "y", "z"].map { key -> Wii.ExtensionField in
        let field = try axes.field(key)
        try claim(field, 1...10, key: "accelerometer")
        return field
      }
      accelerometer = Wii.ExtensionAccelerometer(x: fields[0], y: fields[1], z: fields[2])
    } else {
      accelerometer = nil
    }
  }
}

extension ProtocolDescription.WiiRemote.ReportMode {
  /// Reads a mode: its id in `idRange` and 1...4 blocks that stay inside the report data, in
  /// offset order and without overlap.
  fileprivate init(reader: WiiReader) throws {
    typealias Block = ProtocolDescription.WiiRemote.Block
    id = UInt8(try reader.number("id", Int(Self.idRange.lowerBound)...Int(Self.idRange.upperBound)))
    blocks = try reader.list("blocks", 1...4, allowed: ["kind", "offset", "length"]) {
      let name = try $0.string("kind")
      guard let kind = ProtocolDescription.WiiRemote.BlockKind(rawValue: name) else {
        throw $0.fail("kind", "\(name) is not a block kind")
      }
      return Block(
        kind: kind,
        offset: try $0.number("offset", 0...(Self.dataLength - 1)),
        length: try $0.number("length", kind.lengths)
      )
    }
    var end = 0
    for block in blocks {
      guard block.offset >= end else {
        throw reader.fail("blocks", "blocks are in offset order and do not overlap")
      }
      end = block.offset + block.length
    }
    guard end <= Self.dataLength, Set(blocks.map(\.kind)).count == blocks.count else {
      throw reader.fail(
        "blocks",
        "blocks end by byte \(Self.dataLength) and each kind appears once"
      )
    }
    guard blocks.first?.kind == .buttons || id == 0x3D else {
      throw reader.fail("blocks", "a mode other than 0x3D starts with the Buttons block")
    }
  }
}

extension ProtocolDescription.WiiRemote.Step {
  /// Reads the script under `key`: 1...16 steps.
  fileprivate static func list(_ reader: WiiReader, _ key: String) throws -> [Self] {
    try reader.list(
      key,
      1...16,
      allowed: ["kind", "report", "data", "address", "bytes", "length", "block"]
    ) { try Self(reader: $0) }
  }

  /// Reads a step; a field the step's kind does not use is rejected.
  private init(reader: WiiReader) throws {
    let kind = try reader.string("kind")
    let used: Set<String>
    switch kind {
    case "Report":
      used = ["kind", "report", "data"]
      self = .report(
        id: UInt8(try reader.number("report", 0x10...0x1A)),
        data: try reader.bytes("data", 1...20)
      )
    case "Write":
      used = ["kind", "address", "bytes"]
      self = .write(address: try reader.address(), bytes: try reader.bytes("bytes", 1...16))
    case "Read":
      used = ["kind", "address", "length"]
      self = .read(address: try reader.address(), length: try reader.number("length", 1...16))
    case "Sensitivity":
      used = ["kind", "address", "block"]
      self = .sensitivity(block: try reader.number("block", 1...2), address: try reader.address())
    case "IRMode":
      used = ["kind", "address"]
      self = .irMode(address: try reader.address())
    case "MotionPlusMode":
      used = ["kind", "address"]
      self = .motionPlusMode(address: try reader.address())
    default:
      throw reader.fail("kind", "\(kind) is not a step kind")
    }
    guard reader.keys == used else {
      throw reader.fail("kind", "a \(kind) step sets exactly \(used.sorted())")
    }
  }
}
