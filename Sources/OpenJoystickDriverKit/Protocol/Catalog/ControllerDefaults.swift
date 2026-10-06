import Foundation

/// The user's global tuning defaults, from `Defaults.json` beside the `Controllers` directory.
///
/// A key here sits above the driver default and below every record and profile layer. It applies
/// to each controller whose family reads that key. A file that fails validation is ignored whole
/// and reported in ``problem``.
public struct ControllerDefaults: Equatable, Sendable {
  /// The `$schema` that OJD writes.
  public static let schemaID =
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    + "Resources/Schemas/v1beta1/defaults.schema.json"
  /// The `$schema` values OJD accepts. A version that is not here is rejected.
  public static let knownSchemaIDs: Set<String> = [schemaID]

  /// The file that was read, whether or not it exists.
  public let url: URL
  /// The valid `tuning` values; ``ControllerTuning/none`` when the file is absent or invalid.
  public let tuning: ControllerTuning
  /// Why OJD ignored the file, or nil when it applied it or the file does not exist.
  public let problem: String?

  /// `~/Library/Application Support/OpenJoystickDriver/Defaults.json`.
  public static var userFile: URL { file(besides: ControllerRecordSet.userDirectory) }

  /// `Defaults.json` in the directory that holds `controllers`.
  public static func file(besides controllers: URL) -> URL {
    controllers.deletingLastPathComponent().appendingPathComponent("Defaults.json")
  }

  /// Reads and validates `url`. A missing file holds no defaults.
  public static func load(from url: URL = userFile) -> Self {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
      return Self(url: url, tuning: .none, problem: nil)
    } catch {
      return Self(url: url, tuning: .none, problem: "cannot read the file: \(error)")
    }
    do { return Self(url: url, tuning: try validate(data), problem: nil) } catch {
      return Self(
        url: url,
        tuning: .none,
        problem: ControllerRecordSet.problemDescription(error)
      )
    }
  }

  /// The `tuning` of a `defaults.schema.json` document, range-checked as a record's is.
  public static func validate(_ data: Data) throws -> ControllerTuning {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let document = object as? [String: Any]
    else { throw ControllerRecordProblem("the file is not a JSON object") }
    guard let schema = document["$schema"] as? String, knownSchemaIDs.contains(schema) else {
      throw ControllerRecordProblem(
        "$schema must be one of \(knownSchemaIDs.sorted().joined(separator: ", "))"
      )
    }
    guard Set(document.keys) == ["$schema", "tuning"], let tuning = document["tuning"] else {
      throw ControllerRecordProblem("the file must hold exactly $schema and tuning")
    }
    do {
      let section = try JSONSerialization.data(withJSONObject: tuning)
      return try JSONDecoder().decode(ControllerRecordDocument.Tuning.self, from: section).tuning
    } catch let error as DecodingError {
      throw ControllerRecordProblem(
        ControllerRecordSet.problemDescription(error)
          .replacingOccurrences(of: "record.", with: "tuning.")
      )
    }
  }
}
