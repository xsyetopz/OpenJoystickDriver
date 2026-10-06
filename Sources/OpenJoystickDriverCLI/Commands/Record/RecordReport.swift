import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

/// Where `ojd record` reads and writes user controller records, and how it reads its input.
enum RecordStore {
  /// The user record directory; tests replace it.
  @TaskLocal
  static var directory = ControllerRecordSet.userDirectory

  /// Reads stdin for the `-` operand; tests replace it.
  @TaskLocal
  static var standardInput: @Sendable () -> Data = {
    FileHandle.standardInput.readDataToEndOfFile()
  }

  static func load() -> ControllerRecordSet { ControllerRecordSet.load(userDirectory: directory) }

  /// The persona files OJD reads, beside the record directory as in the user's support folder.
  static func personaFiles() -> [VirtualPersonaFile] {
    VirtualHIDProfileOverrideStore(
      directory: directory.deletingLastPathComponent()
        .appendingPathComponent("Personas", isDirectory: true)
    ).files
  }

  /// The bytes of `FILE`, or of stdin for `-`.
  static func read(_ path: String) throws -> Data {
    if path == "-" { return standardInput() }
    do { return try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.record.error.unreadable",
          path,
          error.localizedDescription
        )
      )
    }
  }

  /// Prints each skipped user file on stderr.
  static func warn(_ files: [ControllerRecordFile]) {
    for file in files {
      CLIOutput.stderr(
        CLILocalized.format(
          "cli.record.skipped",
          file.url.path,
          file.problem ?? ""
        )
      )
    }
  }
}

/// The `VVVV:PPPP` operand of `record show` and `record remove`.
struct RecordIdentity: ExpressibleByArgument, Equatable, Sendable {
  let identity: ControllerIdentity

  init?(argument: String) {
    guard let (vendorID, productID) = ControllerSelection.model(argument) else { return nil }
    identity = ControllerIdentity(vendorID: vendorID, productID: productID)
  }

  var text: String {
    deviceIdentity(vendorID: Int(identity.vendorID), productID: Int(identity.productID))
  }
}

/// How OJD reaches a record's controller. The raw values are stable identifiers.
enum RecordTransport: String, Encodable, Equatable {
  case hid
  case usb

  init(_ record: ControllerRecord) { self = record.usesRawUSB ? .usb : .hid }
}

/// Whether the signed USB extension can claim a raw-USB controller. Its USB entitlement is a
/// product list Apple signs, so a user record cannot add a product to it.
enum RecordUSBExtension: String, Encodable, Equatable {
  case claims
  case doesNotClaim = "does-not-claim"

  init?(_ record: ControllerRecord) {
    guard record.usesRawUSB else { return nil }
    let claimed =
      record.identity.vendorID == USBDriverKitExtensionConfiguration.microsoftVendorID
      && USBDriverKitExtensionConfiguration.microsoftProductIDs.contains(record.identity.productID)
    self = claimed ? .claims : .doesNotClaim
  }
}

/// A user file OJD skipped, and why.
struct SkippedRecord: Encodable, Equatable {
  let file: String
  let problem: String

  init(_ file: ControllerRecordFile) {
    self.file = file.url.path
    problem = file.problem ?? ""
  }

  init(_ file: VirtualPersonaFile) {
    self.file = file.url.path
    problem = file.problem ?? ""
  }

  /// The `Defaults.json` OJD ignored, or nil when it applied the file or the file is absent.
  init?(_ defaults: ControllerDefaults?) {
    guard let defaults, let problem = defaults.problem else { return nil }
    file = defaults.url.path
    self.problem = problem
  }
}

/// One record in `record list --json`.
struct RecordEntry: Encodable, Equatable {
  let identity: String
  let vendorID: Int
  let productID: Int
  let family: String
  let layer: String
  let file: String?

  init(_ record: ControllerRecord) {
    identity = deviceIdentity(
      vendorID: Int(record.identity.vendorID),
      productID: Int(record.identity.productID)
    )
    vendorID = Int(record.identity.vendorID)
    productID = Int(record.identity.productID)
    family = record.family
    layer = record.layer.rawValue
    file = record.userFile?.path
  }
}

/// A JSON document re-encoded as it was read, for the record body of `record show --json`.
enum RecordJSON: Encodable, Equatable {
  case object([String: Self])
  case array([Self])
  case string(String)
  case integer(Int)
  case number(Double)
  case bool(Bool)
  case null

  init(data: Data) throws { self.init(try JSONSerialization.jsonObject(with: data)) }

  init(_ value: Any) {
    switch value {
    case let object as [String: Any]: self = .object(object.mapValues(Self.init))
    case let array as [Any]: self = .array(array.map(Self.init))
    case let string as String: self = .string(string)
    // swiftlint:disable:next legacy_objc_type
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        self = .bool(number.boolValue)
      } else if let integer = Int(exactly: number.doubleValue) {
        self = .integer(integer)
      } else {
        self = .number(number.doubleValue)
      }
    default: self = .null
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .object(let object): try container.encode(object)
    case .array(let array): try container.encode(array)
    case .string(let string): try container.encode(string)
    case .integer(let integer): try container.encode(integer)
    case .number(let number): try container.encode(number)
    case .bool(let bool): try container.encode(bool)
    case .null: try container.encodeNil()
    }
  }
}
