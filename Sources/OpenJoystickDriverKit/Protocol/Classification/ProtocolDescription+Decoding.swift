import Foundation

// The steps ``ProtocolDescription/decode(_:fileName:)`` runs, in the order it runs them.
extension ProtocolDescription {
  /// Decodes the property list `data` into a document, or throws the problem naming `fileName`.
  static func decodedDocument(
    _ data: Data,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> Document {
    do {
      return try DocumentCoder.decode(
        Document.self,
        from: data,
        file: fileName,
        userInfo: [.startupConditionsAllowed: true]
      )
    } catch {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): "
          + ControllerRecordSet.problemDescription(
            error,
            includingCode: false,
            document: "description"
          )
      )
    }
  }

  /// Throws unless the header and the family name of `document` are valid.
  static func requireValidHeader(
    _ document: Document,
    fileName: String
  ) throws(ProtocolDescriptionProblem) {
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: document.apiVersion,
      kind: document.kind,
      expected: kind
    ) {
      throw ProtocolDescriptionProblem(
        problem.code ?? .invalidProtocolDescription,
        "\(fileName): \(problem.message)"
      )
    }
    guard
      document.family.range(of: "\\A[A-Z][A-Za-z0-9]*\\z", options: .regularExpression) != nil
    else {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): \(document.family) is not an UpperCamelCase family name"
      )
    }
  }

  /// Throws when two interface signatures of `document` have the same identity, or when the
  /// document sets a parameter its family does not read.
  static func requireDistinctSignaturesAndReadParameters(
    _ document: Document,
    family: PhysicalProtocolID,
    fileName: String
  ) throws(ProtocolDescriptionProblem) {
    var seenSignatures: Set<String> = []
    for signature in document.interfaceSignatures {
      let identity = [
        signature.variant, "\(signature.interfaceClass)", "\(signature.interfaceSubclass)",
        "\(signature.interfaceProtocol)", signature.interfaceNumber.map(String.init) ?? "",
      ].joined(separator: "/")
      guard seenSignatures.insert(identity).inserted else {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): interfaceSignatures names \(identity) twice"
        )
      }
    }
    let unreadParameters = Set(document.parameters.keys).subtracting(family.readParameters)
    guard unreadParameters.isEmpty else {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): \(family.rawValue) reads no parameter(s) "
          + unreadParameters.sorted().joined(separator: ", ")
      )
    }
  }

  /// Throws unless `fileName` is the file name of `family`, and unless `document` sets
  /// `displayName` and `defaults.input.layouts` exactly when the family is documented.
  static func requireFileNameAndDocumentedFields(
    _ document: Document,
    family: PhysicalProtocolID,
    fileName: String
  ) throws(ProtocolDescriptionProblem) {
    // The file name is checked after the document's own rules.
    let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    if !family.isDocumented, stem == family.rawValue {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): \(family.rawValue) is a built-in family; a documented one needs its own name"
      )
    }
    guard stem == family.descriptionFileStem else {
      throw ProtocolDescriptionProblem(
        .protocolDescriptionFamilyMismatch,
        "\(fileName): file name must be \(family.descriptionFileStem).plist"
      )
    }
    if family.isDocumented {
      guard document.displayName != nil else {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): a documented family sets displayName"
        )
      }
      guard document.defaults?.input?.layouts != nil else {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): a documented family sets defaults.input.layouts"
        )
      }
    } else if document.displayName != nil {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): displayName applies only to a documented family"
      )
    }
  }

  /// The variant `name` of `family`, or a problem when the document declares no such variant.
  static func resolvedVariant(
    named name: String,
    in document: Document,
    family: PhysicalProtocolID,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> PhysicalProtocolVariantID {
    guard let resolved = PhysicalProtocolVariantID(rawValue: name),
      document.variants.contains(resolved)
    else {
      throw ProtocolDescriptionProblem(
        .unknownProtocolVariant,
        "\(fileName): \(family.rawValue) has no variant \(name)"
      )
    }
    return resolved
  }

  /// The interface signatures of `document`, each with its variant resolved.
  static func resolvedSignatures(
    of document: Document,
    family: PhysicalProtocolID,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> [ProtocolInterfaceSignature] {
    var signatures: [ProtocolInterfaceSignature] = []
    for signature in document.interfaceSignatures {
      signatures.append(
        ProtocolInterfaceSignature(
          protocolID: family,
          variant: try resolvedVariant(
            named: signature.variant,
            in: document,
            family: family,
            fileName: fileName
          ),
          interfaceClass: signature.interfaceClass,
          interfaceSubclass: signature.interfaceSubclass,
          interfaceProtocol: signature.interfaceProtocol,
          requiredInterfaceNumber: signature.interfaceNumber
        )
      )
    }
    return signatures
  }

  /// The raw-USB choice of `document`, with each named variant resolved.
  static func resolvedRawUSB(
    of document: Document,
    family: PhysicalProtocolID,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> RawUSB {
    switch document.rawUSB {
    case .none: return .never
    case .always: return .always
    case .variants(let names):
      var chosen: Set<PhysicalProtocolVariantID> = []
      for name in names {
        chosen.insert(
          try resolvedVariant(named: name, in: document, family: family, fileName: fileName)
        )
      }
      return .variants(chosen)
    }
  }

  /// Throws for the first startup, keep-alive, or power-off condition of this description that is
  /// invalid, then for a broken rule or a write outside its scope.
  func requireSoundRules(fileName: String) throws(ProtocolDescriptionProblem) {
    for condition in startupWrites.map(\.condition) + usbStartupWrites.map(\.condition)
      + (receiverPowerOff.map { [$0.condition] } ?? [])
      + (keepAlive?.writes.map(\.payload.condition) ?? [])
    {
      if let problem = conditionProblem(condition, fileName: fileName) { throw problem }
    }
    if let problem = ruleProblem(fileName: fileName) { throw problem }
    if let violation = scopeViolation {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): \(violation.description)"
      )
    }
  }
}
