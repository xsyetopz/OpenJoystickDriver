import Foundation

/// The stable error codes of OpenJoystickDriver, listed in `Resources/ErrorCodes.plist`.
///
/// A code never changes meaning and is never reused. Look codes up on the wiki page `Error-Codes`.
///
/// The E3xxx cases carry the names of `ApplicationServiceRemappingRPCError.Code`, except
/// `remappingUnexpected`, because `unexpected` names E2001. Case names are unique across areas.
public enum ErrorCode: String, Codable, Sendable, CaseIterable {
  /// The endpoint is off.
  case endpointDisabled = "E1001"
  /// The service refused the client: it has no grant for the scopes it asked for, or its signature
  /// or proof is not valid.
  case notGranted = "E1002"
  /// The service could not accept a line because it is not valid or came at the wrong time.
  case invalidMessage = "E1003"
  /// The endpoint already serves its limit of connections per transport.
  case tooManyConnections = "E1004"
  /// The client's grant was removed while it was connected.
  case revoked = "E1005"
  /// The client read lines too slowly.
  case tooSlow = "E1006"
  /// The service already runs its limit of virtual gamepads.
  case tooManyFeeds = "E1007"
  /// The virtual gamepad is closed, or the service runs none.
  case feedClosed = "E1008"
  /// The service does not speak the `apiVersion` of a line.
  case unsupportedEndpointVersion = "E1009"
  /// A line has a `kind` that the service does not know or does not accept at that point.
  case unexpectedKind = "E1010"
  /// A line has no `apiVersion` or no `kind`.
  case missingHeader = "E1011"
  /// `ojd` hit an error it does not recognize.
  case unexpected = "E2001"
  /// The text is not an `ojd` command.
  case unknownCommand = "E2002"
  /// The command line has a wrong or missing option or value.
  case usage = "E2003"
  /// The service is not running.
  case serviceUnavailable = "E2004"
  /// The service did not answer in time.
  case serviceTimeout = "E2005"
  /// The service did not complete the request.
  case serviceRequestFailed = "E2006"
  /// The service rejected this `ojd` because it is not signed like the app.
  case peerRejected = "E2007"
  /// A permission is missing.
  case permissionMissing = "E2008"
  /// The command changes or deletes data and needs confirmation.
  case confirmationRequired = "E2009"
  /// The command stopped before it finished.
  case aborted = "E2010"
  /// The profile or record file is not valid.
  case invalidInputFile = "E2011"
  /// No controller, profile, binding or client matches, or more than one does.
  case notFound = "E2012"
  /// The controller cannot do what the command asks now.
  case controllerRequestFailed = "E2013"
  /// OJD is not fully installed, or its signature is not valid.
  case installationProblem = "E2014"
  /// The system did not complete or apply the request.
  case systemRequestFailed = "E2015"
  /// A file could not be read, written or deleted, or it already exists.
  case fileAccessFailed = "E2016"
  /// The client is unsigned or ad-hoc signed, so it cannot be granted access.
  case unsignedClient = "E2017"
  /// `ojd diagnose` found a failed check.
  case diagnoseFailed = "E2018"
  /// The update check did not finish.
  case updateCheckFailed = "E2019"
  /// The installed app is older than this `ojd`.
  case staleInstallation = "E2020"
  /// A repository build of `ojd` could not hand the command to the installed app.
  case installedCLIFailed = "E2021"
  /// The state that the record's parser produced from the captured reports differs from the
  /// expected state.
  case recordTestMismatch = "E2022"
  /// The controller cannot be claimed or released.
  case claimUnsupported = "E2023"
  /// No endpoint client or token has the ID.
  case unknownAccessClient = "E2024"
  /// A client with that kind of signature cannot be granted access.
  case ungrantableClient = "E2025"
  /// The command names no scope to grant.
  case noAccessScope = "E2026"
  /// The service is stopping.
  case serviceStopping = "E2027"
  /// A token with the name exists.
  case duplicateTokenName = "E2028"
  /// The text is not a valid token name.
  case invalidTokenName = "E2029"
  /// The text is not a valid web origin.
  case invalidWebOrigin = "E2030"
  /// The port on 127.0.0.1 is in use or cannot be opened.
  case webPortUnavailable = "E2031"
  /// A token with origins cannot have the `control` scope.
  case controlScopeWithOrigins = "E2032"
  /// The program could not be started.
  case launchFailed = "E2033"
  /// The service stopped accepting requests.
  case requestListenerStopped = "E2034"
  /// The file that records why the request listener stopped cannot be used.
  case damagedListenerFailureRecord = "E2035"
  /// No app answered the test notification in time.
  case noApplicationAnswered = "E2036"
  /// Notifications are not allowed for OJD.
  case notificationsDenied = "E2037"
  /// The selected controller has no speaker.
  case speakerUnavailable = "E2038"
  /// The audio file is not an uncompressed PCM WAV file.
  case unsupportedAudioFile = "E2039"
  /// The extension on the controller did not answer its setup.
  case extensionHandshakeFailed = "E2040"
  /// The controller is not connected or not ready for remapping.
  case controllerUnavailable = "E3001"
  /// The selected Joy-Con could not be paired.
  case joyConPairUnavailable = "E3002"
  /// The controller does not report motion data.
  case motionUnavailable = "E3003"
  /// A value in the request is larger than the service accepts.
  case argumentTooLarge = "E3004"
  /// The active profile list is damaged and could not be loaded.
  case corruptLibrary = "E3005"
  /// Another profile has the name.
  case duplicateName = "E3006"
  /// The request has missing or invalid arguments.
  case invalidArguments = "E3007"
  /// The profile is not valid.
  case invalidProfile = "E3008"
  /// The profile library would become too large.
  case librarySizeExceeded = "E3009"
  /// A profile with the identifier already exists.
  case profileAlreadyExists = "E3010"
  /// The profile changed elsewhere after it was loaded.
  case profileUpdateConflict = "E3011"
  /// The library already holds the most profiles it allows.
  case profileCountExceeded = "E3012"
  /// No profile has the identifier.
  case profileNotFound = "E3013"
  /// The service could not encode its reply.
  case responseEncodingFailed = "E3014"
  /// The reply is larger than the service can send.
  case responseTooLarge = "E3015"
  /// The remapping engine is not available.
  case routerEngineUnavailable = "E3016"
  /// Neither the profile library nor the remapping engine is available.
  case routerLibraryAndEngineUnavailable = "E3017"
  /// The profile library is not available.
  case routerLibraryUnavailable = "E3018"
  /// The remapping router has shut down.
  case routerShutDown = "E3019"
  /// The service could not confirm whether the last profile change was saved.
  case transactionUnreconciled = "E3020"
  /// A profile file could not be read.
  case unreadableLibrary = "E3021"
  /// Damaged profile files must be repaired or removed before profiles can change.
  case profileRecoveryRequired = "E3022"
  /// A profile file could not be written.
  case unwritableLibrary = "E3023"
  /// The remapping service hit an error it does not recognize.
  case remappingUnexpected = "E3024"
  /// The profile produces no output.
  case profileProducesNoOutput = "E3025"
  /// The Joy-Con pair profile takes its gyro from the other Joy-Con.
  case motionGyroNotSelected = "E3026"
  /// No remapping profile is active for the controller, so it does not process motion.
  case motionProfileInactive = "E3027"
  /// The controller's remapping session changed while the request ran.
  case motionSessionChanged = "E3028"
  /// A profile from an installed package cannot be changed.
  case packageProfileReadOnly = "E3029"
  /// An action needs Post Event (Accessibility) access, which is not granted.
  case postEventAccessMissing = "E3030"
  /// An action needs Automation access, which is not granted.
  case automationAccessMissing = "E3031"
  /// An action needs to send keys while Secure Input blocks them.
  case secureInputEnabled = "E3032"
  /// A system action failed.
  case systemActionFailed = "E3033"
  /// CoreMIDI refused to create the virtual MIDI source for a MIDI destination.
  case midiSourceRefused = "E3034"
  /// The package manifest `mod.plist` is missing or invalid.
  case invalidManifest = "E4001"
  /// The package requires a different version of OJD than the one that runs.
  case requiresExcludesVersion = "E4002"
  /// A file of the package is invalid, missing or not listed in `mod.plist`.
  case invalidPackageContent = "E4003"
  /// The package covers a controller, persona or profile that other files or another installed
  /// package already hold.
  case packageClash = "E4004"
  /// A package with the name is already installed.
  case packageAlreadyInstalled = "E4005"
  /// No installed package has the name.
  case packageNotInstalled = "E4006"
  /// The package folder could not be changed.
  case packageStoreUnwritable = "E4007"
  /// A document has no `apiVersion`, or its `apiVersion` is not supported.
  case unsupportedAPIVersion = "E5001"
  /// A protocol description is invalid.
  case invalidProtocolDescription = "E5002"
  /// A protocol description names a family that differs from its file name.
  case protocolDescriptionFamilyMismatch = "E5003"
  /// A protocol description lists a variant that its family does not have.
  case unknownProtocolVariant = "E5004"
  /// The access file `AccessGrants.plist` is damaged.
  case damagedAccessGrants = "E5005"
  /// The key file `PortKeyInstallation.key` cannot be read or is not 32 bytes.
  case damagedPortKey = "E5006"
  /// A controller record or patch is invalid.
  case invalidControllerRecord = "E5007"
  /// An SDL_GameControllerDB line matched a controller but cannot drive it.
  case sdlLineRejected = "E5008"
  /// `ojd migrate` could not convert a document, which stays unchanged.
  case documentNotMigrated = "E5009"
  /// A stored document is not an XML property list, or holds a `date` or `data` value.
  case invalidDocumentForm = "E5010"

  /// The part of the product that raises a code; the first digit of the number.
  public enum Domain: String, CaseIterable, Sendable {
    /// The endpoint that serves clients over the local socket and the WebSocket.
    case endpoint = "Endpoint"
    /// The `ojd` command line.
    case commandLine = "CLI"
    /// Remapping profiles and the remapping engine.
    case remapping = "Remapping"
    /// Mod packages.
    case mod = "Mod"
    /// The documents and records that OJD reads.
    case document = "Document"

    /// The start of every code of the domain: `E` and the domain's digit.
    public var codePrefix: String {
      switch self {
      case .endpoint: "E1"
      case .commandLine: "E2"
      case .remapping: "E3"
      case .mod: "E4"
      case .document: "E5"
      }
    }

    /// The `Localizable.strings` key of the name of the area.
    public var areaKey: String {
      switch self {
      case .endpoint: "cli.explain.group.areaEndpoint"
      case .commandLine: "cli.explain.group.areaCli"
      case .remapping: "cli.explain.group.areaRemapping"
      case .mod: "cli.explain.group.areaMod"
      case .document: "cli.explain.group.areaDocument"
      }
    }
  }

  /// The area that raises the code.
  public var domain: Domain {
    switch self {
    case .endpointDisabled, .notGranted, .invalidMessage, .tooManyConnections, .revoked, .tooSlow,
      .tooManyFeeds, .feedClosed, .unsupportedEndpointVersion, .unexpectedKind, .missingHeader:
      .endpoint
    case .unexpected, .unknownCommand, .usage, .serviceUnavailable, .serviceTimeout,
      .serviceRequestFailed, .peerRejected, .permissionMissing, .confirmationRequired, .aborted,
      .invalidInputFile, .notFound, .controllerRequestFailed, .installationProblem,
      .systemRequestFailed, .fileAccessFailed, .unsignedClient, .diagnoseFailed,
      .updateCheckFailed, .staleInstallation, .installedCLIFailed, .recordTestMismatch,
      .claimUnsupported, .unknownAccessClient, .ungrantableClient, .noAccessScope,
      .serviceStopping, .duplicateTokenName, .invalidTokenName, .invalidWebOrigin,
      .webPortUnavailable, .controlScopeWithOrigins, .launchFailed, .requestListenerStopped,
      .damagedListenerFailureRecord, .noApplicationAnswered, .notificationsDenied,
      .speakerUnavailable, .unsupportedAudioFile, .extensionHandshakeFailed:
      .commandLine
    case .controllerUnavailable, .joyConPairUnavailable, .motionUnavailable, .argumentTooLarge,
      .corruptLibrary, .duplicateName, .invalidArguments, .invalidProfile, .librarySizeExceeded,
      .profileAlreadyExists, .profileUpdateConflict, .profileCountExceeded, .profileNotFound,
      .responseEncodingFailed, .responseTooLarge, .routerEngineUnavailable,
      .routerLibraryAndEngineUnavailable, .routerLibraryUnavailable, .routerShutDown,
      .transactionUnreconciled, .unreadableLibrary, .profileRecoveryRequired, .unwritableLibrary,
      .remappingUnexpected, .profileProducesNoOutput, .motionGyroNotSelected,
      .motionProfileInactive, .motionSessionChanged, .packageProfileReadOnly,
      .postEventAccessMissing, .automationAccessMissing, .secureInputEnabled,
      .systemActionFailed, .midiSourceRefused:
      .remapping
    case .invalidManifest, .requiresExcludesVersion, .invalidPackageContent, .packageClash,
      .packageAlreadyInstalled, .packageNotInstalled, .packageStoreUnwritable:
      .mod
    case .unsupportedAPIVersion, .invalidProtocolDescription, .protocolDescriptionFamilyMismatch,
      .unknownProtocolVariant, .damagedAccessGrants, .damagedPortKey, .invalidControllerRecord,
      .sdlLineRejected, .documentNotMigrated, .invalidDocumentForm:
      .document
    }
  }

  /// What went wrong and how to fix it, in the language of the user.
  public var localizedExplanation: String {
    Localization().string("error.\(rawValue).message")
  }
}

extension ErrorCode {
  /// The code that typed text names: surrounding whitespace and letter case do not matter.
  /// `ojd explain` and the app's Explain Error Code read codes through this.
  public init?(typed text: String) {
    self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
  }
}
