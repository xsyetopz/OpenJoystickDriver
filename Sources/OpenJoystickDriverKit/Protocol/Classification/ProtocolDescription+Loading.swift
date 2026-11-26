import Foundation

extension ProtocolDescription {
  /// The descriptions of the files `urls`, and a problem for each file that is not a valid
  /// description and for each family that has no file; `source` names where the files are, in the
  /// problem of a missing one.
  ///
  /// The problems come in family order, a missing file at its family's place, then those of the
  /// files that name no family in file-name order. Files of one name are taken in path order, and
  /// each after the first that names a family is a problem naming both files and is not loaded. A
  /// file that cannot be read is ``ErrorCode/fileAccessFailed``. The bundled descriptions and
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
      let name = "\(protocolID.descriptionFileStem).plist"
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
    let names = Set(PhysicalProtocolID.allCases.map { "\($0.descriptionFileStem).plist" })
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
    try decodeDocument(data, fileName: fileName)
  }

  /// Decodes one description from `data`; throws a problem when the document is invalid or its
  /// family does not match the stem of `fileName`.
  private static func decodeDocument(
    _ data: Data,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> Self {
    let document = try decodedDocument(data, fileName: fileName)
    try requireValidHeader(document, fileName: fileName)
    let famID =
      PhysicalProtocolID.allCases.first { $0.rawValue == document.family }
      ?? PhysicalProtocolID(documented: document.family)
    try requireDistinctSignaturesAndReadParameters(document, family: famID, fileName: fileName)
    try requireFileNameAndDocumentedFields(document, family: famID, fileName: fileName)
    let signatures = try resolvedSignatures(of: document, family: famID, fileName: fileName)
    let rawUSBChoice = try resolvedRawUSB(of: document, family: famID, fileName: fileName)
    func variant(named name: String) throws(ProtocolDescriptionProblem) -> PhysicalProtocolVariantID
    {
      try resolvedVariant(named: name, in: document, family: famID, fileName: fileName)
    }
    var tuningByVariant: [PhysicalProtocolVariantID: ControllerTuning] = [:]
    for (name, perVariant) in document.defaults?.variantTuning ?? [:] {
      tuningByVariant[try variant(named: name)] = perVariant
    }
    var rumbleByVariant: [PhysicalProtocolVariantID: RumbleOutputTemplate] = [:]
    for (name, template) in document.defaults?.variantRumble ?? [:] {
      rumbleByVariant[try variant(named: name)] = template
    }
    var start: InputStart?
    if let startDocument = document.inputStart {
      var startVariants: Set<PhysicalProtocolVariantID> = []
      for name in startDocument.variants { startVariants.insert(try variant(named: name)) }
      start = InputStart(action: startDocument.action, variants: startVariants)
    }
    let resolvedStartup = try resolvedUSBStartup(
      document.defaults?.session?.startup,
      namedPackets: document.defaults?.session?.namedPackets,
      fileName: fileName
    )
    let description = Self(
      family: famID,
      displayName: document.displayName,
      variants: document.variants,
      storesVariant: document.storesVariant,
      endpoints: document.endpoints,
      rawUSB: rawUSBChoice,
      recordSections: document.recordSections,
      sessionKeys: document.sessionKeys,
      tuningKeys: document.tuningKeys,
      rawUSBTuningKeys: document.rawUSBTuningKeys,
      macOSOwnedOutput: document.macOSOwnedOutput,
      inputStart: start,
      interfaceSignatures: signatures,
      parameters: document.parameters,
      parameterRules: document.parameterRules,
      writeTransports: document.writeTransports,
      controls: document.controls,
      recordCapabilities: document.recordCapabilities,
      rumbleTemplate: document.defaults?.session?.rumble,
      startupWrites: document.defaults?.session?.startup?.hid ?? [],
      usbStartupWrites: resolvedStartup,
      receiverPowerOff: document.defaults?.receiverPowerOff,
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
      wiiRemote: document.defaults?.session?.wiiRemote,
      inputLayouts: document.defaults?.input?.layouts,
      hidUsageMap: document.defaults?.input?.usageMap,
      hidUsageShapes: document.defaults?.input?.shapes ?? [],
      tuning: document.defaults?.tuning,
      variantTuning: tuningByVariant,
      variantRumble: rumbleByVariant
    )
    try description.requireSoundRules(fileName: fileName)
    return description
  }

  /// The raw-USB startup packets of `startup`: its own, or the named packets it refers to, each
  /// with the condition of its reference.
  ///
  /// A reference to a packet the description lacks fails.
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
}
