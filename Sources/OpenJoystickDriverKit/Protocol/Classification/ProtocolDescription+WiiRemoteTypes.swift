import Foundation

extension ProtocolDescription.WiiRemote {
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
}
