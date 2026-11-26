extension ControllerInputLayout {
  /// A digital control, pressed while any of its fields has a set bit.
  public struct Button: Equatable, Sendable {
    /// The control the button drives.
    public let control: Control
    /// The bit fields of which any set bit presses the button.
    public let fields: [ReportBitField]
  }

  /// One stick axis.
  ///
  /// The raw value grows right on X and down on Y, as in HID.
  public struct Axis: Equatable, Sendable {
    /// The stick axis the value drives.
    public let control: Control
    /// The bits of the value and the raw range that scales to -1...1.
    public let field: ReportValueField
    /// Whether the scaled value is negated.
    public let isInverted: Bool
    /// A signed axis centered on 0 whose positive and negative sides share one divisor,
    /// `maximum`: the raw value divided by `maximum`, clamped, so the lowest value reads -1.
    public let isSymmetric: Bool

    /// The raw value scaled to -1...1 around the middle of `minimum...maximum`, clamped.
    ///
    /// For 0...255 the center is 128, 0 reads -1 and 255 reads 1. A symmetric axis divides by
    /// `maximum` instead. The arithmetic is in `Double`, which holds every 32-bit raw value.
    func value(in bytes: [UInt8]) -> Float {
      let raw = Double(field.raw(in: bytes))
      let low = Double(field.minimum)
      let high = Double(field.maximum)
      let normalized: Double
      if isSymmetric {
        normalized = max(-1, min(1, raw / high))
      } else {
        let center = low + (high - low + 1) / 2
        let offset = raw - center
        let span = offset >= 0 ? high - center : center - low
        normalized = max(-1, min(1, offset / span))
      }
      return Float(isInverted ? -normalized : normalized)
    }
  }

  /// One source of the hat; the first source that reads a direction wins.
  public enum HatSource: Equatable, Sendable {
    /// Values 0 to 7 read north, then clockwise to north-west; any other value is at rest. With
    /// `neutralUntilNonzero`, 0 also reads at rest until the field has been nonzero in the
    /// session, for a pad that sends 0 before its hat is live.
    case eightWay(ReportBitField, neutralUntilNonzero: Bool)
    /// One field per direction; opposing directions cancel.
    case directions(
      up: ReportBitField,
      right: ReportBitField,
      down: ReportBitField,
      left: ReportBitField
    )
    /// The field, as a number, names a direction; a value the table lacks is at rest.
    case table(ReportBitField, [Int: HatDirection])
  }

  /// An analog value scaled to 0 to 1, a button that reads as fully pulled, or both.
  public struct Trigger: Equatable, Sendable {
    /// The analog value; nil when the trigger has none.
    public let analog: ReportValueField?
    /// The bit field that reads as a fully pulled trigger; nil when the trigger has none.
    public let button: ReportBitField?

    /// The trigger position in `bytes`, fully pulled when its button is set.
    ///
    /// The analog value scales from `minimum` to `maximum` and is clamped to 0...1.
    func value(in bytes: [UInt8]) -> UnipolarValue {
      if button?.isSet(in: bytes) == true { return UnipolarValue(normalized: 1) }
      guard let analog else { return UnipolarValue(normalized: 0) }
      let low = Double(analog.minimum)
      let unit = (Double(analog.raw(in: bytes)) - low) / (Double(analog.maximum) - low)
      return UnipolarValue(normalized: Float(max(0, min(1, unit))))
    }
  }

  /// The contacts of a multi-touch report that stand for controls, for a pad that taps a phone
  /// screen for an app's key map.
  ///
  /// The place a contact first touches fixes what it drives until it lifts: within `radius` of a
  /// stick's center it drags that stick, otherwise it holds the nearest spot within `radius`, and
  /// elsewhere it drives nothing.
  public struct Touch: Equatable, Sendable {
    /// Where the contacts sit in the report.
    public struct Contacts: Equatable, Sendable {
      /// The first bit of slot 0.
      public let bitOffset: Int
      /// The bits from one slot to the next.
      public let stride: Int
      /// The number of slots.
      public let slots: Int
      /// The number of leading slots that hold a contact.
      public let count: ReportBitField
      /// The tip switch, set while the contact touches, counted from the start of its slot.
      public let tip: ReportBitField
      /// The contact ID, counted from the start of its slot.
      public let id: ReportBitField
      /// The X position, counted from the start of its slot.
      public let x: ReportBitField
      /// The Y position, counted from the start of its slot.
      public let y: ReportBitField

      /// Each field of each slot at its place in the report, and the count.
      var fields: [ReportBitField] {
        (0..<slots).flatMap { slot in
          [tip, id, x, y].map {
            ReportBitField(bitOffset: bitOffset + slot * stride + $0.bitOffset, bitSize: $0.bitSize)
          }
        } + [count]
      }
    }

    /// A place that holds a control while a contact that started there touches.
    public struct Spot: Equatable, Sendable {
      /// The control the spot holds: a button, a D-pad direction, or a trigger pulled fully.
      public let control: Control
      /// The X position of the spot.
      public let x: Int
      /// The Y position of the spot.
      public let y: Int
    }

    /// The stick axis one touch axis drives.
    public struct StickAxis: Equatable, Sendable {
      /// The stick axis.
      public let control: Control
      /// Whether a larger touch position reads as a smaller axis value.
      public let isInverted: Bool
    }

    /// A stick a contact drags from its center.
    public struct Stick: Equatable, Sendable {
      /// The X position of the center.
      public let x: Int
      /// The Y position of the center.
      public let y: Int
      /// The distance from the center that reads as full deflection.
      public let travel: Int
      /// The stick axis the touch X position drives.
      public let alongX: StickAxis
      /// The stick axis the touch Y position drives.
      public let alongY: StickAxis
    }

    /// What a contact drives, fixed where it first touches.
    enum Role: Equatable {
      /// A spot's control.
      case spot(Control)
      /// The stick at this index.
      case stick(Int)
      /// Nothing.
      case none
    }

    /// Where the contacts sit in the report.
    public let contacts: Contacts
    /// The distance from a spot or stick center within which a contact starts on it.
    public let radius: Int
    /// The spots.
    public let spots: [Spot]
    /// The sticks.
    public let sticks: [Stick]

    /// Every control the spots and sticks drive.
    var controls: Set<Control> {
      Set(spots.map(\.control) + sticks.flatMap { [$0.alongX.control, $0.alongY.control] })
    }

    /// The touching contacts in `bytes`: ID and position.
    func touches(in bytes: [UInt8]) -> [(id: Int, x: Int, y: Int)] {
      (0..<min(contacts.count.value(in: bytes), contacts.slots)).compactMap { slot in
        let start = contacts.bitOffset + slot * contacts.stride
        func read(_ field: ReportBitField) -> Int {
          ReportBitField(bitOffset: start + field.bitOffset, bitSize: field.bitSize).value(
            in: bytes
          )
        }
        guard read(contacts.tip) != 0 else { return nil }
        return (read(contacts.id), read(contacts.x), read(contacts.y))
      }
    }

    /// What a contact that first touches at `x`, `y` drives.
    func role(x: Int, y: Int) -> Role {
      func squaredDistance(_ otherX: Int, _ otherY: Int) -> Int {
        (x - otherX) * (x - otherX) + (y - otherY) * (y - otherY)
      }
      let reach = radius * radius
      if let index = sticks.firstIndex(where: { squaredDistance($0.x, $0.y) <= reach }) {
        return .stick(index)
      }
      let nearest = spots.min { squaredDistance($0.x, $0.y) < squaredDistance($1.x, $1.y) }
      guard let nearest, squaredDistance(nearest.x, nearest.y) <= reach else { return .none }
      return .spot(nearest.control)
    }
  }
}
