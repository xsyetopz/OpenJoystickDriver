import Foundation

extension ControllerRecordDocument {
  /// Throws unless `apiVersion` and `kind` name a controller record.
  static func requireHeader(in container: KeyedDecodingContainer<DocumentKey>) throws {
    let apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
    let documentKind = try container.decodeOptional(String.self, for: "kind")
    guard
      let problem = OpenJoystickDriverAPI.headerProblem(
        apiVersion: apiVersion,
        kind: documentKind,
        expected: kind
      )
    else { return }
    if problem.code != nil { throw problem }
    throw DecodingError.dataCorruptedError(
      forKey: DocumentKey("kind"),
      in: container,
      debugDescription: problem.message
    )
  }

  /// Throws when every mode is idle and the record still holds a section that serves controls.
  static func requireNoControlSectionsForIdleModes(
    _ modes: [ModeDocument],
    in container: KeyedDecodingContainer<DocumentKey>,
    codingPath: [any CodingKey]
  ) throws {
    guard modes.allSatisfy({ $0.idle != nil }) else { return }
    let controlSections: Set<String> = [
      "usb", "bluetoothLE", "capabilities", "server", "route", "heldByAppleDriver", "input",
      "tuning", "validations",
    ]
    guard container.allKeys.allSatisfy({ !controlSections.contains($0.stringValue) }) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("modes")],
          debugDescription: "a record whose modes are all idle has no section that serves controls"
        )
      )
    }
  }

  /// Throws for the first of `values`, named by key, that is present and empty.
  static func requireNonEmpty(
    _ values: [(key: String, value: String?)],
    codingPath: [any CodingKey]
  ) throws {
    for (key, value) in values where value?.isEmpty == true {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must not be empty"
        )
      )
    }
  }

  /// Decodes the optional string at `key` as a case of `Choice`, or throws `expecting`.
  static func decodeChoice<Choice: RawRepresentable>(
    for key: String,
    expecting description: String,
    in container: KeyedDecodingContainer<DocumentKey>
  ) throws -> Choice? where Choice.RawValue == String {
    try container.decodeOptional(String.self, for: key).map { name in
      guard let parsed = Choice(rawValue: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: DocumentKey(key),
          in: container,
          debugDescription: description
        )
      }
      return parsed
    }
  }

  /// Throws for the first validation that names a mode the record does not hold.
  static func requireValidationModes(
    _ validations: [ControllerValidation],
    in modes: [ModeDocument],
    codingPath: [any CodingKey]
  ) throws {
    guard
      let index = validations.firstIndex(where: { validation in
        !modes.contains { $0.id == validation.modeID }
      })
    else { return }
    let path = ["validations", String(index), "mode"].map(DocumentKey.init)
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: codingPath + path,
        debugDescription: "mode \(validations[index].modeID) is not a mode of the record"
      )
    )
  }
}
