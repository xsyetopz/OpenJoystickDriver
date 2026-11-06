import Foundation

extension VirtualDevice {
  /// Where a document came from, which decides whether a header problem names a file.
  enum Source {
    /// A file of this name.
    case file(String)
    /// A document held in memory, such as one the caller reads and names itself.
    case unnamed
  }

  /// The `apiVersion` and `kind` of a document, read before the rest so that a document of
  /// another version is refused for its version whatever else it holds.
  private struct Header: Decodable {
    /// The `apiVersion` as written; nil when absent.
    let apiVersion: Value?
    /// The `kind` as written; nil when absent.
    let kind: Value?

    /// A header member of any scalar type, kept as text for the header problem.
    struct Value: Decodable {
      /// The member as text.
      let text: String

      /// Reads the member as text, whatever its scalar type.
      init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
          self.text = text
        } else if let number = try? container.decode(Double.self) {
          self.text = "\(number)"
        } else if let flag = try? container.decode(Bool.self) {
          self.text = "\(flag)"
        } else {
          self.text = "a value that is not a string"
        }
      }
    }
  }

  /// The members of a `virtual-device.schema.json` document, before the persona and match rules.
  private struct Document: Decodable {
    /// The `match` object of a selection.
    struct Match: Decodable {
      /// The vendor ID.
      let vendorID: Int
      /// The product ID.
      let productID: Int
      /// The unit ID; nil for the whole model.
      let unit: String?

      /// The members of `match`.
      enum CodingKeys: String, CodingKey, CaseIterable {
        /// The vendor ID.
        case vendorID
        /// The product ID.
        case productID
        /// The unit ID.
        case unit
      }

      /// Decodes `match`, refusing a member it does not name.
      init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try container.decode(Int.self, forKey: .vendorID)
        productID = try container.decode(Int.self, forKey: .productID)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
      }
    }

    /// The `identity` object of a definition.
    struct Identity: Decodable {
      /// The vendor ID.
      let vendorID: Int
      /// The product ID.
      let productID: Int
      /// The version number; nil when absent.
      let version: Int?
      /// The product name.
      let productName: String
      /// The manufacturer name.
      let manufacturer: String

      /// The members of `identity`.
      enum CodingKeys: String, CodingKey, CaseIterable {
        /// The vendor ID.
        case vendorID
        /// The product ID.
        case productID
        /// The version number.
        case version
        /// The product name.
        case productName
        /// The manufacturer name.
        case manufacturer
      }

      /// Decodes `identity`, refusing a member it does not name.
      init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try container.decode(Int.self, forKey: .vendorID)
        productID = try container.decode(Int.self, forKey: .productID)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        productName = try container.decode(String.self, forKey: .productName)
        manufacturer = try container.decode(String.self, forKey: .manufacturer)
      }
    }

    /// The persona name, not yet checked against the personas.
    let persona: String?
    /// The `match` object; nil for a definition.
    let match: Match?
    /// The layout name, not yet checked against the layouts.
    let layout: String?
    /// The transport name, not yet checked.
    let transport: String?
    /// The glyph family name, not yet checked.
    let labels: String?
    /// Whether SDL recognizes the device with its default hints.
    let worksWithDefaultSDLHints: Bool?
    /// The `identity` object.
    let identity: Identity?

    /// The members of the document; the header members are read by ``Header``.
    enum CodingKeys: String, CodingKey, CaseIterable {
      /// The `apiVersion`, read by ``Header``.
      case apiVersion
      /// The `kind`, read by ``Header``.
      case kind
      /// The persona.
      case persona
      /// The model selection.
      case match
      /// The report layout.
      case layout
      /// The transport.
      case transport
      /// The glyph family.
      case labels
      /// The identity.
      case identity
      /// Whether SDL recognizes the device with its default hints.
      case worksWithDefaultSDLHints
    }

    /// Decodes the document, refusing a member it does not name.
    init(from decoder: any Decoder) throws {
      try decoder.rejectUnknownKeys(CodingKeys.self)
      let container = try decoder.container(keyedBy: CodingKeys.self)
      persona = try container.decodeIfPresent(String.self, forKey: .persona)
      match = try container.decodeIfPresent(Match.self, forKey: .match)
      layout = try container.decodeIfPresent(String.self, forKey: .layout)
      transport = try container.decodeIfPresent(String.self, forKey: .transport)
      labels = try container.decodeIfPresent(String.self, forKey: .labels)
      worksWithDefaultSDLHints = try container.decodeIfPresent(
        Bool.self,
        forKey: .worksWithDefaultSDLHints
      )
      identity = try container.decodeIfPresent(Identity.self, forKey: .identity)
    }
  }

  /// Decodes one `virtual-device.schema.json` document. `requiresMatch` refuses a document
  /// without `match`, which would otherwise be read as a persona definition.
  ///
  /// - Throws: ``DocumentHeaderProblem`` carrying E5001 when `apiVersion` or `kind` is not the
  ///   supported one, and ``ControllerRecordProblem`` for any other violation of the schema.
  static func decode(
    _ data: Data,
    source: Source,
    requiresMatch: Bool
  ) throws -> Self {
    let decoder = JSONDecoder()
    let document: Document
    do {
      let header = try decoder.decode(Header.self, from: data)
      if let problem = OpenJoystickDriverAPI.headerProblem(
        apiVersion: header.apiVersion?.text,
        kind: header.kind?.text,
        expected: kind
      ) {
        let located: String
        switch source {
        case .file(let name): located = problem.located(in: name).message
        case .unnamed: located = problem.message
        }
        throw DocumentHeaderProblem(code: .unsupportedAPIVersion, located)
      }
      document = try decoder.decode(Document.self, from: data)
    } catch let error as DecodingError {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        ControllerRecordSet.problemDescription(error, document: "virtualDevice")
      )
    }
    guard let persona = document.persona.flatMap(VirtualHIDProfileID.init)
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "persona must be one of "
          + VirtualHIDProfileID.allCases.map(\.rawValue).joined(separator: ", ")
      )
    }
    if requiresMatch, document.match == nil {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "the file must hold match")
    }
    let match = try document.match.map(Self.match)
    let layout = try document.layout.map { value in
      guard let layout = VirtualDeviceLayout(rawValue: value) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "layout must be one of "
            + VirtualDeviceLayout.allCases.map(\.rawValue).joined(separator: ", ")
        )
      }
      return layout
    }
    if let transport = document.transport, !["USB", "Bluetooth"].contains(transport) {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "transport must be USB or Bluetooth"
      )
    }
    let labels = try document.labels.map { value in
      guard let labels = VirtualIdentityGlyphFamily(rawValue: value) else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "labels must be Xbox or Generic"
        )
      }
      return labels
    }
    let identity = try document.identity.map(Self.identity)
    if match != nil {
      guard layout == nil, document.transport == nil, document.worksWithDefaultSDLHints == nil
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "a file with match selects a persona and holds no layout, transport, or "
            + "worksWithDefaultSDLHints"
        )
      }
    } else {
      guard layout != nil, document.transport != nil, labels != nil,
        document.worksWithDefaultSDLHints != nil, let identity, identity.versionNumber != nil
      else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "a persona definition must hold layout, transport, labels, worksWithDefaultSDLHints, "
            + "and identity with version"
        )
      }
    }
    return Self(
      persona: persona,
      match: match,
      layout: layout,
      transport: document.transport,
      labels: labels,
      worksWithDefaultSDLHints: document.worksWithDefaultSDLHints,
      identity: identity
    )
  }

  /// The model, and optionally the unit, that a document's `match` names.
  ///
  /// - Throws: `ControllerRecordProblem` when a vendor ID, product ID or unit is out of range.
  private static func match(_ match: Document.Match) throws -> VirtualHIDProfileOverrideStore.Model
  {
    if let unit = match.unit, ControllerPortKey(rawValue: unit) == nil {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "match.unit is not a unit ID")
    }
    return VirtualHIDProfileOverrideStore.Model(
      vendorID: try id(match.vendorID, "match.vendorID", from: 1),
      productID: try id(match.productID, "match.productID", from: 0),
      unit: match.unit
    )
  }

  /// The identity of a document's `identity` object.
  ///
  /// - Throws: `ControllerRecordProblem` when a name is empty or an ID is out of range.
  private static func identity(_ fields: Document.Identity) throws -> Identity {
    func text(_ key: String, _ value: String) throws -> String {
      guard !value.isEmpty else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "identity.\(key) must be a nonempty string"
        )
      }
      return value
    }
    let version = try fields.version.map { try id($0, "identity.version", from: 0) }
    return Identity(
      vendorID: try id(fields.vendorID, "identity.vendorID", from: 1),
      productID: try id(fields.productID, "identity.productID", from: 0),
      versionNumber: version.map(Int.init),
      productName: try text("productName", fields.productName),
      manufacturer: try text("manufacturer", fields.manufacturer)
    )
  }

  /// The ID in `minimum...65535` that `value` holds.
  ///
  /// - Throws: `ControllerRecordProblem` naming `name` when `value` is outside that range.
  private static func id(_ value: Int, _ name: String, from minimum: Int) throws -> UInt16 {
    guard value >= minimum, let id = UInt16(exactly: value) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "\(name) must be \(minimum)...65535"
      )
    }
    return id
  }
}
