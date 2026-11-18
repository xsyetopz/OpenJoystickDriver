import Foundation
import OpenJoystickDriverKit

/// How long a timed capture runs, as the `--duration` of `ojd controller capture` and
/// `ojd record draft`: a number of seconds above 0.
enum CaptureDuration {
  /// The duration the sheet starts with, as `ojd record draft`.
  static let defaultSeconds = 10.0

  /// Returns the seconds `text` names in `locale`, or nil when it is not a finite number above 0.
  ///
  /// - Parameters:
  ///   - text: The text of the duration field.
  ///   - locale: The locale whose number format the text follows.
  /// - Returns: The seconds `text` names in `locale`, or nil when it is not a finite number above
  ///   0.
  static func parse(_ text: String, locale: Locale = .current) -> Double? {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    guard let number = formatter.number(from: text.trimmingCharacters(in: .whitespaces)) else {
      return nil
    }
    let seconds = number.doubleValue
    return seconds.isFinite && seconds > 0 ? seconds : nil
  }

  /// Returns the text the field starts with.
  ///
  /// - Parameters:
  ///   - seconds: The duration.
  ///   - locale: The locale whose number format the text follows.
  /// - Returns: The text the field starts with.
  static func text(for seconds: Double, locale: Locale = .current) -> String {
    return seconds.formatted(.number.locale(locale).precision(.fractionLength(0...3)))
  }
}

/// Collects the packets a controller sends and receives during a span of time, as
/// `ojd controller capture --duration` and `ojd record draft` do.
enum ControllerPacketCapture {
  /// The pause between reads of the packet log, the CLI's polling interval.
  static let pollIntervalNanoseconds: UInt64 = 16_000_000

  /// Returns the packets that arrive after the call, read from `read` every
  /// ``pollIntervalNanoseconds`` until `seconds` have passed on `uptime`.
  ///
  /// - Parameters:
  ///   - seconds: How long to collect.
  ///   - read: Reads the packet log.
  ///   - uptime: Returns the uptime in nanoseconds.
  ///   - sleep: Waits for the number of nanoseconds.
  /// - Returns: The packets that arrive after the call, read from `read` every
  ///   ``pollIntervalNanoseconds`` until `seconds` have passed on `uptime`.
  /// - Throws: The error of a failed read, or `CancellationError` when the task is cancelled.
  static func collect(
    seconds: Double,
    read: @Sendable () async throws -> [PacketLogEntry],
    uptime: @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
    sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
  ) async throws -> [PacketLogEntry] {
    var cursor = PacketLogSnapshotCursor(snapshot: try await read())
    let start = uptime()
    let limit = UInt64(seconds * 1_000_000_000)
    var packets: [PacketLogEntry] = []
    while uptime() - start < limit {
      packets += cursor.consume(snapshot: try await read())
      try await sleep(pollIntervalNanoseconds)
    }
    return packets
  }

  /// Returns the packets of `device`, read from `gateway`.
  ///
  /// - Parameters:
  ///   - device: The controller to read.
  ///   - gateway: The gateway that streams the packets.
  ///   - seconds: How long to collect.
  /// - Returns: The packets of `device`, read from `gateway`.
  /// - Throws: The error of a failed read, or `CancellationError` when the task is cancelled.
  static func collect(
    from device: ApplicationServiceDeviceDescription,
    gateway: any ControllerDiagnosticsGateway,
    seconds: Double
  ) async throws -> [PacketLogEntry] {
    let selector = ControllerReference.session(device.sessionToken)
    return try await collect(seconds: seconds) { try await gateway.packetLog(for: selector) }
  }

  /// Returns the captured packets as the JSON the Developer tools export.
  ///
  /// - Parameter packets: The captured packets.
  /// - Returns: The captured packets as the JSON the Developer tools export.
  /// - Throws: The error of the JSON encoder.
  static func exportData(_ packets: [PacketLogEntry]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(packets)
  }

  /// Returns the suggested file name of a capture of `device`.
  ///
  /// - Parameter device: The captured controller.
  /// - Returns: The suggested file name of a capture of `device`.
  static func fileName(for device: ApplicationServiceDeviceDescription) -> String {
    unsafe String(
      format: "OpenJoystickDriver-packets-%04X-%04X.json",
      device.vendorID,
      device.productID
    )
  }
}

/// Drafts a controller record from a capture, as `ojd record draft` does.
enum ControllerRecordDrafting {
  /// The error of a capture from which no layout could be drafted.
  struct NoLayout: Error, Equatable {
    /// The vendor and product ID of the controller.
    let identity: String

    /// The message for the sheet.
    var message: String {
      OJDLocalized.formatted("ui.controllers.draftRecord.noLayout", identity)
    }
  }

  /// Returns the report descriptor of the controller model, read from the system.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The report descriptor of the controller model, read from the system.
  static func physicalDescriptor(for device: ApplicationServiceDeviceDescription) -> [UInt8]? {
    PlatformHosts.current.physicalReportDescriptor(
      vendorID: Int(device.vendorID),
      productID: Int(device.productID)
    )
  }

  /// Returns the record drafted from the input reports among `packets` and the controller's HID
  /// report `descriptor`.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - packets: The captured packets.
  ///   - descriptor: The report descriptor of the controller, or nil.
  /// - Returns: The record drafted from the input reports among `packets` and the controller's HID
  ///   report `descriptor`.
  /// - Throws: ``NoLayout`` when no control could be read and the model's bundled record already
  ///   names its family.
  static func draft(
    for device: ApplicationServiceDeviceDescription,
    packets: [PacketLogEntry],
    descriptor: [UInt8]?
  ) throws -> ControllerRecordDraft {
    let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
    guard
      let draft = ControllerRecordDraft(
        model: model,
        bundled: ControllerRecordSet.bundled.records[model] != nil,
        descriptor: descriptor,
        reports: packets.filter { $0.direction == .received }.map(\.reportBytes)
      )
    else { throw NoLayout(identity: model.description) }
    return draft
  }

  /// The error of a record that cannot be drafted from the SDL_GameControllerDB line.
  struct SDLDraftFailure: Error, Equatable {
    /// The message for the notice.
    let message: String
  }

  /// Returns the record drafted from the SDL_GameControllerDB line of the controller, as
  /// `ojd record draft --from-sdl` does.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The record that names the `HIDDescriptor` family and the converted usage map.
  /// - Throws: ``SDLDraftFailure`` when the controller is not readable as a HID device, has a
  ///   bundled record, fails the descriptor contract, or has no line the conversion accepts.
  static func sdlDraft(
    for device: ApplicationServiceDeviceDescription
  ) throws(SDLDraftFailure) -> ControllerRecordDraft {
    let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
    guard
      let pad = PlatformHosts.current.physicalDevice(
        vendorID: Int(device.vendorID),
        productID: Int(device.productID)
      )
    else {
      let message = OJDLocalized.formatted(
        "ui.controllers.draftRecordFromSDL.noPad",
        model.description
      )
      throw SDLDraftFailure(message: message)
    }
    do {
      return try ControllerRecordDraft(model: model, sdlDevice: pad)
    } catch {
      throw SDLDraftFailure(
        message: error.message(identity: model.description, localize: OJDLocalized.string)
      )
    }
  }

  /// Returns the record drafted from the interfaces of a connected device that OJD does not serve,
  /// as `ojd record draft` does.
  ///
  /// - Parameters:
  ///   - model: The vendor and product ID of the device.
  ///   - read: Reads the device from the system by vendor and product ID.
  /// - Returns: The drafted record, or nil when the system does not list the device or no
  ///   interface reports its class triple.
  static func unservedDraft(
    model: ControllerModelID,
    _ read: (Int, Int) -> PhysicalDevice? = {
      PlatformHosts.current.physicalDevice(vendorID: $0, productID: $1)
    }
  ) -> ControllerRecordDraft? {
    read(Int(model.vendorID), Int(model.productID)).flatMap {
      ControllerRecordDraft(model: model, device: $0)
    }
  }

  /// Returns the suggested file name of the record, `vvvv-pppp.plist`.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The suggested file name of the record, `vvvv-pppp.plist`.
  static func fileName(for device: ApplicationServiceDeviceDescription) -> String {
    fileName(for: ControllerModelID(vendorID: device.vendorID, productID: device.productID))
  }

  /// Returns the suggested file name of the record, `vvvv-pppp.plist`.
  ///
  /// - Parameter model: The controller model.
  /// - Returns: The suggested file name of the record, `vvvv-pppp.plist`.
  static func fileName(for model: ControllerModelID) -> String {
    unsafe String(format: "%04x-%04x.plist", model.vendorID, model.productID)
  }
}
