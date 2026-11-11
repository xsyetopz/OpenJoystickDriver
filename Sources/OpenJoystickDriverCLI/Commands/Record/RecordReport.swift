import ArgumentParser
import Foundation
import OpenJoystickDriverKit

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

  /// Loads the bundled records with the user's records.
  static func load() -> ControllerRecordSet { ControllerRecordSet.load(userDirectory: directory) }

  /// The virtual device files OJD reads, beside the record directory as in the user's support
  /// folder, with the folder it does not read.
  static func virtualDeviceFiles() -> [VirtualPersonaFile] {
    VirtualHIDProfileOverrideStore(
      directory: directory.deletingLastPathComponent()
        .appendingPathComponent(VirtualHIDProfileOverrideStore.directoryName, isDirectory: true)
    ).files
  }

  /// The bytes of `FILE`, or of stdin for `-`.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when the file cannot be read.
  static func read(_ path: String) throws -> Data {
    if path == "-" { return standardInput() }
    do { return try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.record.group.errorUnreadable",
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
          "cli.record.group.skipped",
          file.url.path,
          file.problem ?? ""
        )
      )
    }
  }
}

/// The `VVVV:PPPP` operand of `record show` and `record remove`.
extension ControllerModelID: ExpressibleByArgument {
  /// Parses a `VVVV:PPPP` model operand; fails for any other kind of reference.
  public init?(argument: String) {
    guard case .model(let model) = ControllerReference(argument) else { return nil }
    self = model
  }
}

/// How OJD reaches a record's controller.
///
/// The raw values are stable identifiers.
enum RecordTransport: String, Encodable, Equatable {
  /// Through the HID driver.
  case hid = "HID"
  /// Through raw USB.
  case usb = "USB"

  /// The transport that `record` uses.
  init(_ record: ControllerRecord) { self = record.usesRawUSB ? .usb : .hid }
}

/// Whether the signed USB extension can claim a raw-USB controller.
///
/// Its USB entitlement is a product list Apple signs, so a user record cannot add a product to it.
enum RecordTransportClaim: String, Encodable, Equatable {
  /// The extension can claim the controller.
  case claimed = "Claimed"
  /// The extension cannot claim the controller.
  case unclaimed = "Unclaimed"

  /// The claim state for `record`; nil for a record that does not use raw USB.
  init?(_ record: ControllerRecord) {
    guard let claimed = record.isClaimedByUSBExtension else { return nil }
    self = claimed ? .claimed : .unclaimed
  }
}

/// A user file OJD skipped, and why.
struct SkippedRecord: Encodable, Equatable {
  /// The path of the file.
  let file: String
  /// Why OJD skipped the file.
  let problem: String

  /// Describes a skipped controller record file.
  init(_ file: ControllerRecordFile) {
    self.file = file.url.path
    problem = file.problem ?? ""
  }

  /// Describes a skipped virtual device file.
  init(_ file: VirtualPersonaFile) {
    self.file = file.url.path
    problem = file.problem ?? ""
  }

  /// Describes the `all.patch.plist` OJD ignored; nil when it applied the file or the file is
  /// absent.
  init?(_ defaults: ControllerDefaults?) {
    guard let defaults, let problem = defaults.problem else { return nil }
    file = defaults.url.path
    self.problem = problem
  }
}

/// One record in `record list --json`.
struct RecordEntry: Encodable, Equatable {
  /// The controller model as `VVVV:PPPP`.
  let identity: String
  /// The USB vendor ID.
  let vendorID: Int
  /// The USB product ID.
  let productID: Int
  /// The protocol family.
  let family: String
  /// The record layer.
  let layer: String
  /// The record file, when the record comes from one.
  let file: String?

  /// Describes `record`.
  init(_ record: ControllerRecord) {
    identity = deviceIdentity(
      vendorID: Int(record.model.vendorID),
      productID: Int(record.model.productID)
    )
    vendorID = Int(record.model.vendorID)
    productID = Int(record.model.productID)
    family = record.family
    layer = record.layer.rawValue
    file = record.file?.path
  }
}
