import Foundation

/// Why a protocol description is invalid, in words for the person who wrote it, with the
/// catalog code that names the failure.
struct ProtocolDescriptionProblem: Error, Equatable, Sendable, CustomStringConvertible {
  let code: ErrorCode
  let detail: String

  init(_ code: ErrorCode, _ detail: String) {
    self.code = code
    self.detail = detail
  }

  var description: String { "\(code.rawValue): \(detail)" }
}

/// One family's protocol description (`Resources/Protocols/<file stem>.json`): the interface
/// signatures that bind its variants, the typed parameters its records may set, the facts its
/// driver reads (endpoints, raw USB, record sections, tuning keys, what OJD still
/// sends when macOS serves the controller), and the defaults its records layer over. Drivers read
/// these values; they hold no copy.
struct ProtocolDescription: Sendable {
  /// A parameter's declared type.
  enum ParameterType: Equatable, Sendable {
    /// `true` or absent.
    case flag
    /// One of these names.
    case enumeration([String])
    /// An object of integer fields, each within its range.
    case object([String: ClosedRange<Int>])
  }

  /// The default USB endpoint addresses of a raw-USB family.
  struct Endpoints: Equatable, Sendable {
    let input: Int
    let output: Int
  }

  /// Which variants of a family are reached through raw USB.
  enum RawUSB: Equatable, Sendable {
    case never
    case always
    case variants(Set<PhysicalProtocolVariantID>)

    func applies(to variant: PhysicalProtocolVariantID?) -> Bool {
      switch self {
      case .never: false
      case .always: true
      case .variants(let variants): variant.map(variants.contains) ?? false
      }
    }
  }

  /// A record section the family's driver reads.
  enum RecordSection: String, Sendable {
    /// The record's `input` byte layout.
    case input
    /// A rumble template.
    case rumble
    /// The record's `input.hidUsageMap`.
    case hidUsageMap
    /// The record's `bluetoothLE` section.
    case bluetoothLE
    /// The mode's `protocol.keepAlive`.
    case keepAlive
  }

  /// A rule on the parameters a record sets beyond each parameter's own type.
  struct ParameterRule: Equatable, Sendable {
    enum Kind: String, Sendable {
      /// No parameter is set.
      case none = "None"
      /// At most one of `parameters` is set.
      case atMostOne = "AtMostOne"
      /// Exactly one of `parameters` is set.
      case exactlyOne = "ExactlyOne"
      /// Every one of `parameters` is set whenever any parameter is.
      case requires = "Requires"
    }

    let kind: Kind
    let parameters: Set<String>
    /// The variants the rule applies to; every variant when empty.
    let variants: Set<PhysicalProtocolVariantID>

    func applies(to variant: PhysicalProtocolVariantID?) -> Bool {
      variants.isEmpty || variant.map(variants.contains) ?? false
    }

    /// Why a record that sets `names` breaks the rule, or nil.
    func violation(setting names: Set<String>) -> String? {
      let listed = parameters.sorted().joined(separator: ", ")
      let setCount = names.intersection(parameters).count
      switch kind {
      case .none:
        return names.isEmpty ? nil : "the variant takes no parameters"
      case .atMostOne:
        return setCount <= 1 ? nil : "at most one of \(listed) may be set"
      case .exactlyOne:
        return setCount == 1 ? nil : "exactly one of \(listed) must be set"
      case .requires:
        return names.isEmpty || parameters.isSubset(of: names)
          ? nil : "parameters require \(listed)"
      }
    }
  }

  /// A general `defaults.session` key a family's driver reads beyond the rumble template.
  enum SessionKey: String, Sendable {
    /// The startup writes.
    case startup
    /// The keep-alive.
    case keepAlive
  }

  /// The `kind` of a protocol description.
  static let kind = "ProtocolDescription"

  let family: PhysicalProtocolID
  /// The family's implemented variants; empty when it has one contract.
  let variants: [PhysicalProtocolVariantID]
  /// Whether catalog records store the family's variant; otherwise classification derives it from
  /// the observed transport.
  let storesVariant: Bool
  let endpoints: Endpoints
  let rawUSB: RawUSB
  let recordSections: Set<RecordSection>
  /// The general `defaults.session` keys the driver reads beyond the rumble template, which
  /// `recordSections` governs; none when the description lists none.
  let sessionKeys: Set<SessionKey>
  /// The `tuning` keys the family reads beyond `stickDeadzone` and `frameQueueCapacity` through
  /// IOHID; none when every variant is raw USB.
  let tuningKeys: Set<ControllerTuning.Key>
  /// The `tuning` keys a raw-USB variant reads beyond `stickDeadzone` and `frameQueueCapacity`.
  let rawUSBTuningKeys: Set<ControllerTuning.Key>
  /// What OJD still sends when macOS serves the controller.
  let macOSOwnedOutput: MacOSOwnedOutput
  /// What the user does before a controller of the family sends input; nil when input starts on
  /// its own.
  let inputStart: InputStart?
  let interfaceSignatures: [ProtocolInterfaceSignature]
  /// The parameters records of this family may set, by name.
  let parameters: [String: ParameterType]
  /// The rules a record's parameters obey beyond each parameter's own type.
  let parameterRules: [ParameterRule]
  /// The transports an activation or deactivation write may name.
  let writeTransports: Set<PhysicalTransport>
  /// The controls every controller of the family has; a driver adds only what its record or
  /// layout makes true. Nil for a family whose controls follow its layout.
  let controls: ControllerCapabilities?
  /// The capability deltas a record of this family may declare.
  let recordCapabilities: RecordCapabilityRules
  let rumbleTemplate: RumbleOutputTemplate?
  /// The family's HID initialization writes, sent when a controller starts unless its record
  /// carries its own.
  let startupWrites: [RecordStartupWrite]
  /// The family's raw-USB initialization packets, sent when a controller starts unless its record
  /// carries its own.
  let usbStartupWrites: [USBStartupWrite]
  /// The family's keep-alive: its interval, the one place the interval is set, and the fixed
  /// writes of each run.
  let keepAlive: KeepAlive?
  /// The HID reports sent in order when a Valve controller is activated, each limited by its
  /// transport. Only the Valve families have them.
  let activation: [RecordStartupWrite]
  /// The HID reports sent in order when a Valve controller is deactivated, each limited by its
  /// transport. Only the Valve families have them.
  let deactivation: [RecordStartupWrite]
  /// The family-specific `defaults.session` keys the document sets, as written.
  let presentSessionFields: Set<String>
  /// The family's subcommand reports: the report id, the rolling counter rule and the startup
  /// requests. Only `NintendoSwitch1` has them.
  let subcommands: SubcommandPlan?
  /// The family's named packets, which a record selects by id in `protocol.initialization`.
  /// Only `XboxGIP` has them.
  let namedPackets: NamedPacketPlan?
  /// The startup attempts a raw-USB handshake makes before it fails. Only `XboxGIP` has it.
  let handshakeAttempts: Int?
  /// The most startup resends after announces before the first input. Only `XboxGIP` has it.
  let announceResendLimit: Int?
  /// The USB interface that carries commands and their replies. Only `NintendoSwitch2` has it.
  let commandChannel: CommandChannel?
  /// The zero-amplitude packets the rumble refresh sends after a stop. Only `NintendoSwitch2` has
  /// it.
  let trailingStopPackets: Int?
  let inputLayout: ControllerInputLayout?
  /// The map every `HIDDescriptor` record layers over (``HIDUsageMap``).
  let hidUsageMap: HIDUsageMap?
  /// Descriptor shapes that select another map, first match first.
  let hidUsageShapes: [HIDUsageShape]
  let tuning: ControllerTuning?
  /// Tuning defaults by stored variant, layered over `tuning` for that variant.
  let variantTuning: [PhysicalProtocolVariantID: ControllerTuning]
  /// Rumble templates by stored variant, each overriding `rumbleTemplate` for that variant.
  let variantRumble: [PhysicalProtocolVariantID: RumbleOutputTemplate]

  /// The capability deltas a record may declare: exactly this set of present controls (or none),
  /// and rumble absent.
  struct RecordCapabilityRules: Equatable, Sendable {
    let presentControls: Set<Control>
    let rumbleAbsent: Bool

    static let none = Self(presentControls: [], rumbleAbsent: false)

    func permits(_ delta: ControllerCapabilityDelta) -> Bool {
      (delta.presentControls.isEmpty || delta.presentControls == presentControls)
        && (!delta.rumbleAbsent || rumbleAbsent)
    }
  }

  /// `inputStart`: the action that starts input on the listed variants, or on every variant when
  /// the list is empty.
  struct InputStart: Equatable, Sendable {
    let action: InputStartAction
    let variants: Set<PhysicalProtocolVariantID>
  }

  /// The action that starts input on a controller of this family and `variant`; nil when input
  /// starts on its own.
  func inputStartAction(variant: PhysicalProtocolVariantID?) -> InputStartAction? {
    guard let inputStart,
      inputStart.variants.isEmpty || variant.map(inputStart.variants.contains) == true
    else { return nil }
    return inputStart.action
  }

  /// The defaults a controller of this family and stored variant starts from: the family's
  /// `tuning` with the variant's layered over it; nil when neither sets a key.
  func tuning(variant: PhysicalProtocolVariantID?) -> ControllerTuning? {
    let layered = (tuning ?? .none).overlaid(by: variant.flatMap { variantTuning[$0] } ?? .none)
    return layered == .none ? nil : layered
  }

  /// The rumble template a controller of this family and stored variant encodes from: the
  /// variant's own when the description sets one, otherwise the family's; nil when neither does.
  func rumbleTemplate(variant: PhysicalProtocolVariantID?) -> RumbleOutputTemplate? {
    variant.flatMap { variantRumble[$0] } ?? rumbleTemplate
  }

  /// The bundled descriptions, by family.
  static let bundled: [PhysicalProtocolID: Self] = {
    do { return try loadBundled() } catch {
      fatalError("[ProtocolDescription] Invalid protocol descriptions: \(error)")
    }
  }()

  private static func loadBundled() throws -> [PhysicalProtocolID: Self] {
    let urls = PhysicalProtocolID.allCases.compactMap {
      Bundle.module.url(forResource: $0.descriptionFileStem, withExtension: "json")
    }
    let catalog = loadCatalog(urls, missing: "the bundle")
    if let problem = catalog.problems.first {
      throw ProtocolDescriptionProblem(problem.code, problem.message)
    }
    return catalog.descriptions
  }

  /// The descriptions of the files `urls`, and a problem for each file that is not a valid
  /// description and for each family that has no file; `source` names where the files are, in
  /// the problem of a missing one. The problems come in family order, a missing file at its
  /// family's place, then those of the files that name no family in file-name order. Files of one
  /// name are taken in path order, and each after the first that names a family is a problem
  /// naming both files and is not loaded. A file that cannot be read is
  /// ``ErrorCode/fileAccessFailed``. The bundled descriptions and
  /// ``RepositoryValidation/descriptions(in:)`` load through this check.
  static func loadCatalog(
    _ urls: [URL],
    missing source: String
  ) -> (descriptions: [PhysicalProtocolID: Self], problems: [RepositoryProblem]) {
    var descriptions: [PhysicalProtocolID: Self] = [:]
    var problems: [RepositoryProblem] = []
    var owners: [PhysicalProtocolID: URL] = [:]
    func load(_ url: URL) {
      let data: Data
      do { data = try RepositoryProblem.read(url) } catch {
        problems.append(error)
        return
      }
      do {
        let description = try decode(data, fileName: url.lastPathComponent)
        if let owner = owners[description.family] {
          problems.append(
            RepositoryProblem(
              file: url.path,
              code: .invalidProtocolDescription,
              message: "\(description.family) is already described by \(owner.path)"
            )
          )
          return
        }
        owners[description.family] = url
        descriptions[description.family] = description
      } catch {
        problems.append(RepositoryProblem(file: url.path, code: error.code, message: error.detail))
      }
    }
    let byName = urls.sorted {
      ($0.lastPathComponent, $0.path) < ($1.lastPathComponent, $1.path)
    }
    for protocolID in PhysicalProtocolID.allCases {
      let name = "\(protocolID.descriptionFileStem).json"
      let files = byName.filter { $0.lastPathComponent == name }
      if files.isEmpty {
        problems.append(
          RepositoryProblem(
            file: name,
            code: .invalidProtocolDescription,
            message: "\(name) is missing from \(source)"
          )
        )
      }
      files.forEach(load)
    }
    let names = Set(PhysicalProtocolID.allCases.map { "\($0.descriptionFileStem).json" })
    byName.filter { !names.contains($0.lastPathComponent) }.forEach(load)
    return (descriptions, problems)
  }

  /// Decodes one description from the file `fileName`, whose stem names the family it holds; the
  /// bundle loads its descriptions through this check.
  ///
  /// A malformed document, an unknown field and a value outside its range are E5002; a file name
  /// that is not the family's, or that no family has, is E5003, after the document itself is
  /// checked; a variant that the family lacks is E5004.
  static func decode(
    _ data: Data,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> Self {
    let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    return try decode(
      data,
      expectedFamily: PhysicalProtocolID.allCases.first { $0.descriptionFileStem == stem },
      fileName: fileName
    )
  }

  private static func decode(
    _ data: Data,
    expectedFamily protocolID: PhysicalProtocolID?,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> Self {
    let document: Document
    do {
      let decoder = JSONDecoder()
      decoder.userInfo[.startupConditionsAllowed] = true
      document = try decoder.decode(Document.self, from: data)
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
    guard let family = PhysicalProtocolID(rawValue: document.family) else {
      throw ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): \(document.family) is not a family"
      )
    }
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
    // The file name is checked after the document's own rules.
    guard let protocolID, family == protocolID else {
      throw ProtocolDescriptionProblem(
        .protocolDescriptionFamilyMismatch,
        "\(fileName): file name must be \(family.descriptionFileStem).json"
      )
    }
    var signatures: [ProtocolInterfaceSignature] = []
    for signature in document.interfaceSignatures {
      guard let variant = PhysicalProtocolVariantID(rawValue: signature.variant),
        document.variants.contains(variant)
      else {
        throw ProtocolDescriptionProblem(
          .unknownProtocolVariant,
          "\(fileName): \(protocolID.rawValue) has no variant \(signature.variant)"
        )
      }
      signatures.append(
        ProtocolInterfaceSignature(
          protocolID: protocolID,
          variant: variant,
          interfaceClass: signature.interfaceClass,
          interfaceSubclass: signature.interfaceSubclass,
          interfaceProtocol: signature.interfaceProtocol,
          requiredInterfaceNumber: signature.interfaceNumber
        )
      )
    }
    var rawUSB = RawUSB.never
    switch document.rawUSB {
    case .none: break
    case .always: rawUSB = .always
    case .variants(let names):
      var variants: Set<PhysicalProtocolVariantID> = []
      for name in names {
        guard let variant = PhysicalProtocolVariantID(rawValue: name),
          document.variants.contains(variant)
        else {
          throw ProtocolDescriptionProblem(
            .unknownProtocolVariant,
            "\(fileName): \(protocolID.rawValue) has no variant \(name)"
          )
        }
        variants.insert(variant)
      }
      rawUSB = .variants(variants)
    }
    func variant(named name: String) throws(ProtocolDescriptionProblem) -> PhysicalProtocolVariantID
    {
      guard let variant = PhysicalProtocolVariantID(rawValue: name),
        document.variants.contains(variant)
      else {
        throw ProtocolDescriptionProblem(
          .unknownProtocolVariant,
          "\(fileName): \(protocolID.rawValue) has no variant \(name)"
        )
      }
      return variant
    }
    var variantTuning: [PhysicalProtocolVariantID: ControllerTuning] = [:]
    for (name, tuning) in document.defaults?.variantTuning ?? [:] {
      variantTuning[try variant(named: name)] = tuning
    }
    var variantRumble: [PhysicalProtocolVariantID: RumbleOutputTemplate] = [:]
    for (name, template) in document.defaults?.variantRumble ?? [:] {
      variantRumble[try variant(named: name)] = template
    }
    var inputStart: InputStart?
    if let document = document.inputStart {
      var variants: Set<PhysicalProtocolVariantID> = []
      for name in document.variants { variants.insert(try variant(named: name)) }
      inputStart = InputStart(action: document.action, variants: variants)
    }
    let usbStartupWrites = try resolvedUSBStartup(
      document.defaults?.session?.startup,
      namedPackets: document.defaults?.session?.namedPackets,
      fileName: fileName
    )
    let description = Self(
      family: protocolID,
      variants: document.variants,
      storesVariant: document.storesVariant,
      endpoints: document.endpoints,
      rawUSB: rawUSB,
      recordSections: document.recordSections,
      sessionKeys: document.sessionKeys,
      tuningKeys: document.tuningKeys,
      rawUSBTuningKeys: document.rawUSBTuningKeys,
      macOSOwnedOutput: document.macOSOwnedOutput,
      inputStart: inputStart,
      interfaceSignatures: signatures,
      parameters: document.parameters,
      parameterRules: document.parameterRules,
      writeTransports: document.writeTransports,
      controls: document.controls,
      recordCapabilities: document.recordCapabilities,
      rumbleTemplate: document.defaults?.session?.rumble,
      startupWrites: document.defaults?.session?.startup?.hid ?? [],
      usbStartupWrites: usbStartupWrites,
      keepAlive: document.defaults?.session?.keepAlive,
      activation: document.defaults?.session?.activation ?? [],
      deactivation: document.defaults?.session?.deactivation ?? [],
      presentSessionFields: document.defaults?.session?.familyFields ?? [],
      subcommands: document.defaults?.session?.subcommands,
      namedPackets: document.defaults?.session?.namedPackets,
      handshakeAttempts: document.defaults?.session?.handshakeAttempts,
      announceResendLimit: document.defaults?.session?.announceResendLimit,
      commandChannel: document.defaults?.session?.commandChannel,
      trailingStopPackets: document.defaults?.session?.trailingStopPackets,
      inputLayout: document.defaults?.input?.layout,
      hidUsageMap: document.defaults?.input?.usageMap,
      hidUsageShapes: document.defaults?.input?.shapes ?? [],
      tuning: document.defaults?.tuning,
      variantTuning: variantTuning,
      variantRumble: variantRumble
    )
    for condition in description.startupWrites.map(\.condition)
      + description.usbStartupWrites.map(\.condition)
      + (description.keepAlive?.writes.map(\.payload.condition) ?? [])
    {
      if let problem = description.conditionProblem(condition, fileName: fileName) {
        throw problem
      }
    }
    if let problem = description.ruleProblem(fileName: fileName) { throw problem }
    if let violation = description.scopeViolation {
      throw ProtocolDescriptionProblem(.invalidProtocolDescription, "\(fileName): \(violation)")
    }
    return description
  }

  /// The raw-USB startup packets of `startup`: its own, or the named packets it refers to, each
  /// with the condition of its reference. A reference to a packet the description lacks fails.
  private static func resolvedUSBStartup(
    _ startup: ControllerRecordDocument.StartupList?,
    namedPackets: NamedPacketPlan?,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> [USBStartupWrite] {
    guard let startup, !startup.packets.isEmpty else { return startup?.usb ?? [] }
    var writes: [USBStartupWrite] = []
    for reference in startup.packets {
      guard let packet = namedPackets?.packet(named: reference.id) else {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): startup names \(reference.id), which is not a named packet"
        )
      }
      do {
        writes.append(try packet.write.with(condition: reference.condition))
      } catch {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): \(error.description)"
        )
      }
    }
    return writes
  }

  /// The fixed keep-alive writes that a controller on `variant` receives from this description.
  /// A keep-alive write has no `when`. A record's mode adds a keep-alive only for a family whose
  /// description declares none.
  func keepAliveWrites(variant: PhysicalProtocolVariantID?) -> [KeepAliveWrite] {
    (keepAlive?.writes ?? []).filter {
      $0.payload.condition.matches(variant: variant, parameters: .none)
    }
  }

  /// The HID startup writes of `phase` that a controller on `variant` whose record sets
  /// `parameters` receives from this description.
  func startupWrites(
    phase: StartupPhase,
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> [RecordStartupWrite] {
    startupWrites.filter {
      $0.phase == phase && $0.condition.matches(variant: variant, parameters: parameters)
    }
  }

  /// The activation reports of a controller reached over `transport`.
  func activationWrites(over transport: PhysicalTransport?) -> [PhysicalOutputWrite] {
    activation.filter { $0.applies(to: transport) }.map(\.write)
  }

  /// The deactivation reports of a controller reached over `transport`.
  func deactivationWrites(over transport: PhysicalTransport?) -> [PhysicalOutputWrite] {
    deactivation.filter { $0.applies(to: transport) }.map(\.write)
  }

  /// The raw-USB startup packets that a controller on `variant` whose record sets `parameters`
  /// receives from this description.
  func usbStartupWrites(
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> [USBStartupWrite] {
    usbStartupWrites.filter { $0.condition.matches(variant: variant, parameters: parameters) }
  }

  /// The tuning keys a controller of this family and stored variant reads: the
  /// always-read keys, and the family's `rawUSBTuningKeys` when the variant is raw USB, otherwise
  /// its `tuningKeys`.
  func tuningScope(variant: PhysicalProtocolVariantID?) -> Set<ControllerTuning.Key> {
    (rawUSB.applies(to: variant) ? rawUSBTuningKeys : tuningKeys)
      .union(ControllerTuning.Key.alwaysRead)
  }
}
