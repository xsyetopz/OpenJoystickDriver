extension ProtocolDescription {
  /// A record section the family's driver reads.
  enum RecordSection: String, Sendable {
    /// The record's `input` byte layout.
    case input
    /// A rumble template.
    case rumble
    /// A player-indicator template.
    case playerIndicator
    /// The record's `input.hidUsageMap`.
    case hidUsageMap
    /// The record's `bluetoothLE` section.
    case bluetoothLE
    /// The mode's `protocol.keepAlive`.
    case keepAlive
  }
}
