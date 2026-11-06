import Foundation

/// The user's global tuning defaults, from the `all` patch `all.patch.json` in the `Controllers`
/// directory.
///
/// The `all` patch is the first patch of the user layer, so a key here sits above the bundled and
/// package values and below every user patch of one model. It applies to each controller whose
/// family reads that key. A file that fails validation is ignored whole and reported in
/// ``problem``.
public struct ControllerDefaults: Equatable, Sendable {
  /// The file that was read, whether or not it exists.
  public let url: URL
  /// The valid `tuning` values; ``ControllerTuning/none`` when the file is absent or invalid.
  public let tuning: ControllerTuning
  /// Why OJD ignored the file, or nil when it applied it or the file does not exist.
  public let problem: String?
  /// The valid patch, or nil when the file is absent or invalid.
  let patch: ControllerPatch?

  /// The file name of the `all` patch.
  public static let fileName = ControllerPatch.Selector.all.fileName

  /// `~/Library/Application Support/OpenJoystickDriver/Controllers/all.patch.json`.
  public static var userFile: URL { file(in: ControllerRecordSet.userDirectory) }

  /// `all.patch.json` in the controller-record directory `controllers`.
  public static func file(in controllers: URL) -> URL {
    controllers.appendingPathComponent(fileName)
  }

  /// Reads and validates `url`.
  ///
  /// A missing file holds no defaults.
  public static func load(from url: URL = userFile) -> Self {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
      return Self(url: url, tuning: .none, problem: nil, patch: nil)
    } catch {
      return Self(url: url, tuning: .none, problem: "cannot read the file: \(error)", patch: nil)
    }
    do {
      let validated = try validate(data, file: url.lastPathComponent)
      return Self(url: url, tuning: validated.tuning, problem: nil, patch: validated.patch)
    } catch {
      return Self(
        url: url,
        tuning: .none,
        problem: ControllerRecordSet.problemDescription(error, document: "tuning"),
        patch: nil
      )
    }
  }

  /// The patch and the range-checked `tuning` of an `all` patch document.
  ///
  /// Like every patch, it refuses text that is not plain UTF-8 and an object that names a member
  /// twice.
  static func validate(
    _ data: Data,
    file: String? = nil
  ) throws -> (patch: ControllerPatch, tuning: ControllerTuning) {
    try ControllerRecordSet.requireUTF8(data)
    guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "the file is not a JSON object")
    }
    let patch = try ControllerPatch.parse(try ControllerRecordSet.ordered(data), file: file)
    guard patch.selector == .all else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "the selector must be all in \(fileName)"
      )
    }
    let values = (patch.body["tuning"]?.members ?? []).filter { $0.value != .null }
    do {
      let section = try JSONSerialization.data(
        withJSONObject: OrderedJSON.object(values).foundationValue()
      )
      return (
        patch, try JSONDecoder().decode(ControllerRecordDocument.Tuning.self, from: section).tuning
      )
    } catch let error as DecodingError {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        ControllerRecordSet.problemDescription(error, document: "tuning")
      )
    }
  }
}
