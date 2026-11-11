import Foundation

extension ProtocolDescription {
  /// `defaults.session.wiiRemote`: the wire facts of the Wii Remote that a table can state, which
  /// are the report layouts, button and LED bits, extension ids, the register scripts and their
  /// timing.
  ///
  /// The state machine that sequences the scripts, the calibration math, the IR pointer and the
  /// speaker codec stay in the driver. Only `NintendoWii` has it.
  struct WiiRemote: Decodable, Equatable, Sendable {
    /// A byte of a block and the bits of it that a field uses.
    struct BitField: Equatable, Sendable {
      /// The byte, counted from the first byte after the report id.
      let byte: Int
      /// The bits of the byte.
      let mask: UInt8
    }

    /// One core button: its control and the bit that is set while it is down.
    struct Button: Equatable, Sendable {
      /// The control the button drives.
      let control: Control
      /// The bit, in the two core button bytes.
      let field: BitField
    }

    /// The two low bits of each accelerometer axis, which the core button bytes carry.
    ///
    /// The high eight bits of the three axes are the three bytes of the `Accelerometer` block.
    struct AccelerometerLowBits: Equatable, Sendable {
      /// The low bits of the X axis; two bits.
      let x: BitField
      /// The low bit of the Y axis.
      let y: BitField
      /// The low bit of the Z axis.
      let z: BitField
    }

    /// What a block of a report mode carries.
    enum BlockKind: String, Equatable, Sendable, CaseIterable {
      /// The two core button bytes.
      case buttons = "Buttons"
      /// The high accelerometer bytes: three, or one in each report of the interleaved pair.
      case accelerometer = "Accelerometer"
      /// The IR camera in the basic format, 10 bytes.
      case irBasic = "IRBasic"
      /// The IR camera in the extended format, 12 bytes.
      case irExtended = "IRExtended"
      /// The IR camera in the full format, 18 bytes of a `0x3E` or `0x3F` report.
      case irFull = "IRFull"
      /// The extension bytes.
      case extensionData = "Extension"

      /// The accepted length of a block of this kind, in bytes.
      var lengths: ClosedRange<Int> {
        switch self {
        case .buttons: 2...2
        case .accelerometer: 1...3
        case .irBasic: 10...10
        case .irExtended: 12...12
        case .irFull: 18...18
        case .extensionData: 1...21
        }
      }
    }

    /// A run of bytes of a report mode.
    struct Block: Equatable, Sendable {
      /// What the bytes are.
      let kind: BlockKind
      /// The first byte, counted from the first byte after the report id.
      let offset: Int
      /// The number of bytes.
      let length: Int
    }

    /// An input report mode and the blocks its report carries.
    struct ReportMode: Equatable, Sendable {
      /// The accepted ids.
      static let idRange: ClosedRange<UInt8> = 0x30...0x3F
      /// The largest number of bytes after the report id.
      static let dataLength = 21

      /// The report id, which is also the mode.
      let id: UInt8
      /// The blocks, in offset order, without overlap.
      let blocks: [Block]
    }

    /// The smallest report mode that carries a set of features.
    struct ModeChoice: Equatable, Sendable {
      /// The features the mode must carry; buttons are always carried.
      let features: Set<BlockKind>
      /// The report mode.
      let mode: UInt8
    }

    /// One value of an extension's six data bytes, assembled from one to three runs of bits.
    struct ExtensionField: Equatable, Sendable {
      /// The runs, most significant first; each mask is contiguous.
      let parts: [BitField]

      /// The width of the value, in bits.
      var bits: Int { parts.reduce(0) { $0 + $1.mask.nonzeroBitCount } }

      /// The value in `data`, the six data bytes.
      func value(in data: [UInt8]) -> Int {
        parts.reduce(0) { value, part in
          let byte = part.byte < data.count ? data[part.byte] : 0
          let width = part.mask.nonzeroBitCount
          return (value << width) | Int((byte & part.mask) >> part.mask.trailingZeroBitCount)
        }
      }
    }

    /// One extension button: its control, its bit and the level of the bit while it is down.
    struct ExtensionButton: Equatable, Sendable {
      /// The control the button drives.
      let control: Control
      /// The bit, in the six data bytes.
      let field: BitField
      /// Whether the bit is set while the button is down; the Nunchuk and the Classic Controller
      /// clear it.
      let pressedWhenSet: Bool
    }

    /// One extension stick axis.
    struct ExtensionStick: Equatable, Sendable {
      /// The axis control.
      let control: Control
      /// The raw value.
      let field: ExtensionField
      /// The distance from the center to the end of the range, in raw steps.
      let halfRange: Int
    }

    /// One extension trigger: the raw value runs from 0 to `2^bits - 1`.
    struct ExtensionTrigger: Equatable, Sendable {
      /// The trigger control.
      let control: Control
      /// The raw value.
      let field: ExtensionField
    }

    /// The three accelerometer axes of an extension, each up to 10 bits.
    struct ExtensionAccelerometer: Equatable, Sendable {
      /// The X axis.
      let x: ExtensionField
      /// The Y axis.
      let y: ExtensionField
      /// The Z axis.
      let z: ExtensionField
    }

    /// How the driver finds the center of an extension stick.
    enum StickCenter: String, Equatable, Sendable {
      /// The first sample after the handshake is the center (`ExtensionCenterFromFirstSample`);
      /// WiiBrew documents no calibration block.
      case firstSample = "FirstSample"
    }

    /// The decode of the six data bytes of an extension.
    struct ExtensionLayout: Equatable, Sendable {
      /// The buttons.
      let buttons: [ExtensionButton]
      /// The sticks.
      let sticks: [ExtensionStick]
      /// The center rule; set exactly when `sticks` is not empty.
      let stickCenter: StickCenter?
      /// The triggers.
      let triggers: [ExtensionTrigger]
      /// The accelerometer, when the extension has one.
      let accelerometer: ExtensionAccelerometer?
    }

    /// An extension kind, the six bytes its id read returns and its data layout.
    struct ExtensionID: Equatable, Sendable {
      /// The kind's name.
      let kind: String
      /// The six bytes of the id.
      let id: [UInt8]
      /// The decode of its data bytes; nil for a kind the description does not decode, such as
      /// the Motion Plus, which the driver decodes itself.
      let layout: ExtensionLayout?
    }

    /// One IR sensitivity level: the two blocks written to the camera.
    struct IRSensitivityLevel: Equatable, Sendable {
      /// The level, 1 for the lowest sensitivity.
      let level: Int
      /// The nine bytes written to `B00000`.
      let block1: [UInt8]
      /// The two bytes written to `B0001A`.
      let block2: [UInt8]
    }

    /// One step of a script.
    enum Step: Equatable, Sendable {
      /// An output report whose data bytes follow the id; the driver adds the rumble bit.
      case report(id: UInt8, data: [UInt8])
      /// A write of `bytes` to the register at `address`.
      case write(address: UInt32, bytes: [UInt8])
      /// A read of `length` bytes from the register at `address`.
      case read(address: UInt32, length: Int)
      /// A write of an IR sensitivity block (1 or 2) of the chosen level to `address`.
      case sensitivity(block: Int, address: UInt32)
      /// A write of the byte of the chosen IR mode to `address`.
      case irMode(address: UInt32)
      /// A write of the byte of the Motion Plus mode that fits the extension to `address`.
      case motionPlusMode(address: UInt32)
    }

    /// The scripts, each a list of steps in send order.
    struct Scripts: Equatable, Sendable {
      /// The extension handshake.
      let handshake: [Step]
      /// The read of the accelerometer calibration from the remote's EEPROM.
      let accelerometerCalibration: [Step]
      /// The Motion Plus activation.
      let motionPlus: [Step]
      /// The IR camera setup.
      let ir: [Step]
      /// The IR camera disable.
      let irStop: [Step]
      /// The speaker setup.
      let speaker: [Step]
      /// The speaker stop.
      let speakerStop: [Step]
    }

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
      coreButtons = buttons
      let low = try root.object("accelerometerLowBits", allowed: ["x", "y", "z"])
      accelerometerLowBits = AccelerometerLowBits(
        x: try low.object("x", allowed: ["byte", "mask"]).bitField(bytes: 0...1),
        y: try low.object("y", allowed: ["byte", "mask"]).bitField(bytes: 0...1),
        z: try low.object("z", allowed: ["byte", "mask"]).bitField(bytes: 0...1)
      )
      let modes = try root.list("reportModes", 1...16, allowed: ["id", "blocks"]) {
        try ReportMode(reader: $0)
      }
      guard Set(modes.map(\.id)).count == modes.count else {
        throw root.fail("reportModes", "a report mode id appears at most once")
      }
      reportModes = modes
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
      modeChoices = choices
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
      extensions = kinds
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
      irSensitivityLevels = levels
      defaultIRSensitivityLevel = defaultLevel
      let formats: [(key: String, kind: BlockKind)] = [
        ("basic", .irBasic), ("extended", .irExtended), ("full", .irFull),
      ]
      let modeObject = try root.object("irModeBytes", allowed: Set(formats.map(\.key)))
      irModeBytes = Dictionary(
        uniqueKeysWithValues: try formats.map {
          ($0.kind, UInt8(try modeObject.number($0.key, 0...255)))
        }
      )
      let plusKeys = ["standalone", "nunchuk", "classic"]
      let plusObject = try root.object("motionPlusModeBytes", allowed: Set(plusKeys))
      motionPlusModeBytes = Dictionary(
        uniqueKeysWithValues: try plusKeys.map { ($0, UInt8(try plusObject.number($0, 0...255))) }
      )
      let scriptObject = try root.object(
        "scripts",
        allowed: [
          "handshake", "accelerometerCalibration", "motionPlus", "ir", "irStop", "speaker",
          "speakerStop",
        ]
      )
      scripts = Scripts(
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

/// Strict reads of one JSON object for the Wii Remote field: every failure names the key.
private struct WiiReader {
  /// The object being read.
  let container: KeyedDecodingContainer<DocumentKey>

  /// The keys the object sets.
  var keys: Set<String> { Set(container.allKeys.map(\.stringValue)) }

  /// Reads `container`, rejecting any key outside `allowed`.
  init(_ container: KeyedDecodingContainer<DocumentKey>, allowed: Set<String>) throws {
    try container.rejectUnknown(allowed: allowed)
    self.container = container
  }

  /// A decoding error at `key`.
  func fail(_ key: String, _ text: String) -> DecodingError {
    .dataCorrupted(
      .init(codingPath: container.codingPath + [DocumentKey(key)], debugDescription: text)
    )
  }

  /// The integer at `key`, inside `range`.
  func number(_ key: String, _ range: ClosedRange<Int>) throws -> Int {
    let value = try container.decode(Int.self, for: key)
    guard range.contains(value) else {
      throw fail(key, "\(key) must be in \(range.lowerBound)...\(range.upperBound)")
    }
    return value
  }

  /// The string at `key`.
  func string(_ key: String) throws -> String { try container.decode(String.self, for: key) }

  /// The string array at `key`.
  func strings(_ key: String) throws -> [String] { try container.decode([String].self, for: key) }

  /// The hex bytes at `key`, `count` bytes long.
  func bytes(_ key: String, _ count: ClosedRange<Int>) throws -> [UInt8] {
    guard let bytes = HexBytes.parse(try string(key)), count.contains(bytes.count) else {
      throw fail(key, "\(key) is \(count.lowerBound)...\(count.upperBound) \(HexBytes.message)")
    }
    return bytes
  }

  /// The 24-bit register address of the `address` key, six uppercase hex digits.
  func address() throws -> UInt32 {
    let text = try string("address")
    guard text.count == 6, text.allSatisfy({ "0123456789ABCDEF".contains($0) }),
      let value = UInt32(text, radix: 16)
    else { throw fail("address", "address is six uppercase hex digits") }
    return value
  }

  /// The `byte` and `mask` of a bit field whose byte lies in `bytes`.
  func bitField(bytes: ClosedRange<Int>) throws -> ProtocolDescription.WiiRemote.BitField {
    .init(byte: try number("byte", bytes), mask: UInt8(try number("mask", 1...255)))
  }

  /// The control named by the `control` key.
  func control() throws -> Control {
    let name = try string("control")
    guard let control = Control(rawValue: name) else {
      throw fail("control", "\(name) is not a control")
    }
    return control
  }

  /// The one to three contiguous runs of bits at `key`, most significant first.
  func field(_ key: String) throws -> ProtocolDescription.WiiRemote.ExtensionField {
    let parts = try list(key, 1...3, allowed: ["byte", "mask"]) { try $0.bitField(bytes: 0...5) }
    for part in parts {
      let run = part.mask >> part.mask.trailingZeroBitCount
      guard run & (run &+ 1) == 0 else { throw fail(key, "a mask is one run of set bits") }
    }
    return .init(parts: parts)
  }

  /// The nested object at `key`, limited to the `allowed` keys.
  func object(_ key: String, allowed: Set<String>) throws -> Self {
    try Self(
      try container.nestedContainer(keyedBy: DocumentKey.self, forKey: DocumentKey(key)),
      allowed: allowed
    )
  }

  /// The array at `key` of `count` entries, each read with `read`.
  func list<Value>(
    _ key: String,
    _ count: ClosedRange<Int>,
    allowed: Set<String>,
    _ read: (Self) throws -> Value
  ) throws -> [Value] {
    var unkeyed = try container.nestedUnkeyedContainer(forKey: DocumentKey(key))
    var values: [Value] = []
    while !unkeyed.isAtEnd {
      let item = try Self(
        try unkeyed.nestedContainer(keyedBy: DocumentKey.self),
        allowed: allowed
      )
      values.append(try read(item))
    }
    guard count.contains(values.count) else {
      throw fail(key, "\(key) names \(count.lowerBound)...\(count.upperBound) entries")
    }
    return values
  }
}
