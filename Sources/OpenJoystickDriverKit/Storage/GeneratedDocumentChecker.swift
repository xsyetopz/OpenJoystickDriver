public import Foundation

/// A document that a generator script returned, checked and encoded.
public struct GeneratedDocument: Equatable, Sendable {
  /// The `kind` of the document.
  public let kind: String
  /// The name of the file that holds the document in its folder, by the naming rule of its store.
  public let fileName: String
  /// The document as an XML property list.
  public let data: Data
}

/// Why a returned document is refused: its key path and the rule it breaks.
public struct GeneratedDocumentProblem: Error, Equatable, Sendable, CustomStringConvertible {
  /// The key path and the rule, in words.
  public let description: String
}

/// Checks the documents of a generator script with the readers that load a hand-written file.
public enum GeneratedDocumentChecker {
  private static let kinds = "Controller, ControllerPatch, VirtualDevice, or Profile"

  /// Checks `tree`, a dictionary that JSON text gave, and encodes it as an XML property list.
  ///
  /// An integer stays an integer and a fractional number becomes a real.
  ///
  /// - Throws: ``GeneratedDocumentProblem`` for a `null` value, a `kind` that no generator writes,
  ///   and any rule that the reader of the kind refuses.
  public static func check(_ tree: [String: Any]) throws -> GeneratedDocument {
    if let keyPath = nullKeyPath(in: tree, keyPath: "") {
      throw GeneratedDocumentProblem(
        description: "\(keyPath) is null; a document holds no null value"
      )
    }
    let data = try DocumentCoder.write(tree)
    let kind = tree["kind"] as? String ?? ""
    do {
      switch kind {
      case ControllerRecordDocument.kind, ControllerPatch.kind:
        let validated = try ControllerRecordSet.validate(data)
        return GeneratedDocument(kind: kind, fileName: validated.fileName, data: data)
      case VirtualDevice.kind:
        let model = try VirtualHIDProfileOverrideStore.parse(data).0
        return GeneratedDocument(kind: kind, fileName: model.fileName, data: data)
      case RemappingProfile.kind:
        let profile = try RemappingProfileFileStore.load(from: data)
        return GeneratedDocument(
          kind: kind,
          fileName: RemappingProfileFileStore.fileName(for: profile.id),
          data: data
        )
      default:
        throw GeneratedDocumentProblem(
          description: kind.isEmpty
            ? "kind is missing; a generated document is a \(Self.kinds)"
            : "kind \(kind) is not generated; use \(Self.kinds)"
        )
      }
    } catch let problem as GeneratedDocumentProblem {
      throw problem
    } catch {
      throw GeneratedDocumentProblem(
        description: ControllerRecordSet.problemDescription(
          error,
          includingCode: false,
          document: kind == RemappingProfile.kind
            ? "profile" : kind == VirtualDevice.kind ? "virtualDevice" : "record"
        )
      )
    }
  }

  /// The key path of the first `null` in `value`, or nil.
  private static func nullKeyPath(in value: Any, keyPath: String) -> String? {
    switch value {
    case is NSNull:
      return keyPath
    case let dictionary as [String: Any]:
      for (key, child) in dictionary.sorted(by: { $0.key < $1.key }) {
        if let found = nullKeyPath(in: child, keyPath: keyPath.isEmpty ? key : "\(keyPath).\(key)")
        {
          return found
        }
      }
    case let list as [Any]:
      for (index, child) in list.enumerated() {
        if let found = nullKeyPath(in: child, keyPath: "\(keyPath)[\(index)]") { return found }
      }
    default:
      break
    }
    return nil
  }
}
