/// A family's subcommand reports (`defaults.session.subcommands` in its protocol description): the
/// report id, the rule of the rolling packet counter that every output report of the family shares,
/// the requests sent in order at startup and the player-indicator subcommand.
///
/// A record never carries one.
struct SubcommandPlan: Equatable, Sendable {
  /// The accepted values of `counterModulus`.
  static let counterModulusRange = 2...256
  /// The accepted number of requests.
  static let requestsRange = 1...16

  /// The id of the output report that carries a subcommand.
  let reportID: UInt8
  /// The counter starts at 0 and the one after `n` is `(n + 1) % counterModulus`.
  let counterModulus: Int
  /// The requests of a startup, in send order.
  let requests: [SubcommandRequest]
  /// The subcommand that lights the player indicator.
  let playerIndicator: PlayerIndicatorSubcommand

  /// Creates a plan; throws when the modulus or request count is outside its range or two SPI reads
  /// share a purpose.
  init(
    reportID: UInt8,
    counterModulus: Int,
    requests: [SubcommandRequest],
    playerIndicator: PlayerIndicatorSubcommand
  ) throws(ControllerRecordProblem) {
    guard Self.counterModulusRange.contains(counterModulus) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.subcommandPlan.counterModulus",
        "a subcommand counterModulus is 2...256"
      )
    }
    guard Self.requestsRange.contains(requests.count) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.subcommandPlan.requestsCount",
        "subcommands name 1...16 requests"
      )
    }
    let purposes = requests.compactMap { $0.spiRead?.purpose }
    guard Set(purposes).count == purposes.count else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.subcommandPlan.spiPurpose",
        "each SPI read purpose appears at most once"
      )
    }
    self.reportID = reportID
    self.counterModulus = counterModulus
    self.requests = requests
    self.playerIndicator = playerIndicator
  }

  /// The counter value that follows `counter`.
  func nextCounter(after counter: UInt8) -> UInt8 {
    UInt8(truncatingIfNeeded: (Int(counter) + 1) % counterModulus)
  }

  /// The request that reads for `purpose`, if any.
  func spiRead(for purpose: SubcommandRequest.SPIRead.Purpose) -> SubcommandRequest? {
    requests.first { $0.spiRead?.purpose == purpose }
  }
}

/// The player-indicator subcommand: its id and the one data byte that lights each player.
struct PlayerIndicatorSubcommand: Equatable, Sendable {
  /// The id of the player-indicator subcommand.
  let subcommand: UInt8
  /// The data byte that lights each player indicator.
  let patterns: [PhysicalPlayerIndicator: UInt8]

  /// Fails unless every indicator has a pattern.
  init(
    subcommand: UInt8,
    patterns: [PhysicalPlayerIndicator: UInt8]
  ) throws(ControllerRecordProblem) {
    guard Set(patterns.keys) == Set(PhysicalPlayerIndicator.allCases) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.subcommandPlan.playerIndicator",
        "a player indicator names a pattern for every indicator"
      )
    }
    self.subcommand = subcommand
    self.patterns = patterns
  }

  /// The data byte that lights `indicator`.
  func pattern(for indicator: PhysicalPlayerIndicator) -> UInt8 {
    guard let pattern = patterns[indicator] else {
      preconditionFailure("a player indicator names a pattern for every indicator")
    }
    return pattern
  }
}

/// One subcommand: its id and either fixed data bytes or an SPI flash read.
struct SubcommandRequest: Equatable, Sendable {
  /// A read of the controller's SPI flash: the address goes out as four little-endian bytes and
  /// then the length.
  struct SPIRead: Equatable, Sendable {
    /// What an SPI read fetches.
    enum Purpose: String, Equatable, Sendable {
      /// The factory calibration of the motion sensors.
      case factoryMotionCalibration = "FactoryMotionCalibration"
      /// The user calibration of the motion sensors.
      case userMotionCalibration = "UserMotionCalibration"
    }

    /// The accepted values of `length`.
    static let lengthRange = 1...29

    /// The SPI flash address.
    let address: UInt32
    /// The number of bytes to read.
    let length: UInt8
    /// What the read fetches.
    let purpose: Purpose
  }

  /// The accepted number of data bytes.
  static let dataRange = 1...16

  /// The subcommand id.
  let subcommand: UInt8
  /// The data bytes that follow the subcommand id.
  let data: [UInt8]
  /// The SPI read the request performs; nil for a fixed-data request.
  let spiRead: SPIRead?

  /// Creates a request with fixed data; throws when the data count is outside `dataRange`.
  init(subcommand: UInt8, data: [UInt8]) throws(ControllerRecordProblem) {
    guard Self.dataRange.contains(data.count) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.subcommandPlan.dataCount",
        "a subcommand request names 1...16 data bytes"
      )
    }
    self.subcommand = subcommand
    self.data = data
    spiRead = nil
  }

  /// Creates a request that reads SPI flash; the data is the address as four little-endian bytes
  /// and the length.
  ///
  /// Throws when the length is outside `SPIRead.lengthRange`.
  init(subcommand: UInt8, spiRead: SPIRead) throws(ControllerRecordProblem) {
    guard SPIRead.lengthRange.contains(Int(spiRead.length)) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.subcommandPlan.spiLength",
        "an SPI read length is 1...29"
      )
    }
    self.subcommand = subcommand
    data =
      (0..<4).map { UInt8(truncatingIfNeeded: spiRead.address >> (8 * UInt32($0))) }
      + [spiRead.length]
    self.spiRead = spiRead
  }
}
