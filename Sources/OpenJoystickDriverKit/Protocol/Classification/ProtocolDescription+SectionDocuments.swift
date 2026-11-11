import Foundation

/// The documents of the description sections a family may declare: endpoints, raw USB,
/// controls, record capabilities, macOS-owned output, parameter declarations and integer fields.
extension ProtocolDescription {
  /// `endpoints`: the default input and output endpoint addresses.
  struct EndpointsDocument: Decodable {
    /// The decoded endpoints.
    let endpoints: Endpoints

    /// Decodes `in` and `out`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["in", "out"])
      let input = try container.decode(Int.self, for: "in")
      let output = try container.decode(Int.self, for: "out")
      guard (0...255).contains(input), (0...255).contains(output) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "endpoints are 0...255")
        )
      }
      endpoints = Endpoints(input: input, output: output)
    }
  }

  /// `rawUSB`: `true` for every variant, or the variants that are raw USB.
  enum RawUSBDeclaration: Decodable {
    /// Every variant is reached through raw USB.
    case always
    /// The named variants are reached through raw USB.
    case variants([String])

    /// Decodes `true` or a nonempty list of unique variant names; `false` or a repeated name is
    /// rejected.
    init(from decoder: any Decoder) throws {
      let single = try decoder.singleValueContainer()
      if let flag = try? single.decode(Bool.self) {
        guard flag else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "rawUSB is true or variants")
          )
        }
        self = .always
        return
      }
      let names = try single.decode([String].self)
      guard !names.isEmpty, Set(names).count == names.count else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "variants are unique, nonempty")
        )
      }
      self = .variants(names)
    }
  }

  /// `controls`: the controls every controller of the family has, as the Xbox layout with
  /// `remove` taken away and `add` put in, plus its digital triggers, touch contacts and motion.
  struct ControlsDocument: Decodable {
    /// The decoded capabilities.
    let value: ControllerCapabilities

    /// Decodes `base`, `remove`, `add`, `digitalTriggers`, `touchContactCount` and `motion`; an
    /// unknown key or a `base` other than `Xbox` is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "base", "remove", "add", "digitalTriggers", "touchContactCount", "motion",
      ])
      var controls: Set<Control> = []
      if let base = try container.decodeOptional(String.self, for: "base") {
        guard base == "Xbox" else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("base")],
              debugDescription: "base is Xbox"
            )
          )
        }
        controls = Control.xboxLayout
      }
      let remove = Set(try container.decodeUniqueList(Control.self, for: "remove") ?? [])
      let add = Set(try container.decodeUniqueList(Control.self, for: "add") ?? [])
      let digital = Set(try container.decodeUniqueList(Control.self, for: "digitalTriggers") ?? [])
      let touch = try container.decodeOptional(Int.self, for: "touchContactCount") ?? 0
      guard remove.isDisjoint(with: add), remove.isSubset(of: controls),
        digital.isSubset(of: [.leftTrigger, .rightTrigger]), (0...10).contains(touch),
        !controls.isEmpty || !add.isEmpty
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "controls remove only base controls, are disjoint, and name at least one control"
          )
        )
      }
      value = ControllerCapabilities(
        controls: controls.subtracting(remove).union(add),
        digitalTriggers: digital,
        touchContactCount: UInt8(touch),
        motion: try container.decodeOptional(Bool.self, for: "motion") ?? false
      )
    }
  }

  /// `recordCapabilities`: the capability deltas a record of the family may declare.
  struct RecordCapabilitiesDocument: Decodable {
    /// The decoded rules.
    let value: RecordCapabilityRules

    /// Decodes `present` and `rumbleAbsent`; any other key or a repeated control is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["present", "rumbleAbsent"])
      let present = Set(try container.decodeUniqueList(Control.self, for: "present") ?? [])
      let rumbleAbsent = try container.decodeOptional(Bool.self, for: "rumbleAbsent") ?? false
      guard !container.allKeys.isEmpty, rumbleAbsent || container.contains(DocumentKey("present"))
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "recordCapabilities names a delta, and rumbleAbsent is true"
          )
        )
      }
      value = RecordCapabilityRules(presentControls: present, rumbleAbsent: rumbleAbsent)
    }
  }

  /// `macOSOwnedOutput`: lighting, rumble and reports OJD still sends to a controller macOS serves.
  struct MacOSOwnedOutputDocument: Decodable {
    /// The decoded output.
    let value: MacOSOwnedOutput

    /// Decodes the keys of the macOS-owned output section; an unknown key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "lightingFeatures", "drivesRumble", "reports", "setsStartupPlayerIndicator",
        "readsStartupFeatures",
      ])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "macOSOwnedOutput is not empty")
        )
      }
      var features: Set<PhysicalLightingFeature> = []
      for name in try container.decodeOptional([String].self, for: "lightingFeatures") ?? [] {
        guard let feature = PhysicalLightingFeature(rawValue: name) else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("lightingFeatures")],
              debugDescription: "unknown lighting feature \(name)"
            )
          )
        }
        features.insert(feature)
      }
      let reports =
        try container.decodeOptional([ControllerRecordDocument.TemplateReport].self, for: "reports")
        ?? []
      value = MacOSOwnedOutput(
        lightingFeatures: features,
        drivesRumble: try container.decodeOptional(Bool.self, for: "drivesRumble") ?? false,
        reports: Set(reports.map(\.report)),
        setsStartupPlayerIndicator: try container.decodeOptional(
          Bool.self,
          for: "setsStartupPlayerIndicator"
        ) ?? false,
        readsStartupFeatures: try container.decodeOptional(Bool.self, for: "readsStartupFeatures")
          ?? false
      )
    }
  }

  /// A parameter declaration: `{type: Flag}`, `{type: Enum, values}` or `{type: Object, fields}`.
  struct Declaration: Decodable {
    /// The decoded parameter type.
    let type: ParameterType

    /// Decodes a `Flag`, an `Enum` with unique UpperCamelCase `values`, or an `Object` with integer
    /// `fields`; an unknown type, key or an empty list is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let name = try container.decode(String.self, for: "type")
      switch name {
      case "Flag":
        try container.rejectUnknown(allowed: ["type"])
        type = .flag
      case "Enum":
        try container.rejectUnknown(allowed: ["type", "values"])
        let values = try container.decode([String].self, for: "values")
        guard !values.isEmpty, Set(values).count == values.count,
          values.allSatisfy({ $0.first?.isUppercase == true })
        else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("values")],
              debugDescription: "values are unique, nonempty UpperCamelCase names"
            )
          )
        }
        type = .enumeration(values)
      case "Object":
        try container.rejectUnknown(allowed: ["type", "fields"])
        let fields = try container.decode([String: IntegerField].self, for: "fields")
        guard !fields.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("fields")],
              debugDescription: "fields must not be empty"
            )
          )
        }
        type = .object(fields.mapValues(\.range))
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("type")],
            debugDescription: "type is Flag, Enum or Object"
          )
        )
      }
    }
  }

  /// An integer field of an object parameter, bounded by `minimum` and `maximum`.
  struct IntegerField: Decodable {
    /// The inclusive range of the field.
    let range: ClosedRange<Int>

    /// Decodes `type` (`Integer`), `minimum` and `maximum`; an unknown key, another type, or a
    /// `minimum` above the `maximum` is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["type", "minimum", "maximum"])
      guard try container.decode(String.self, for: "type") == "Integer" else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("type")],
            debugDescription: "an object field is an integer"
          )
        )
      }
      let minimum = try container.decode(Int.self, for: "minimum")
      let maximum = try container.decode(Int.self, for: "maximum")
      guard minimum <= maximum else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "minimum exceeds maximum")
        )
      }
      range = minimum...maximum
    }
  }
}
