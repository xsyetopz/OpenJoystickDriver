import Foundation
import OpenJoystickDriverKit

/// The `ojd controller show --json` result.
struct ControllerShowReport: Encodable, Equatable {
  /// Who discovered, owns and serves the controller.
  struct Ownership: Encodable, Equatable {
    /// How the service discovered the controller.
    let discoverySource: String
    /// Who owns the controller physically.
    let physical: String
    /// Who owns the controller's HID input.
    let hidInput: String
    /// The client that holds the controller's USB interface exclusively; absent when none does or
    /// the interface names none.
    let owner: USBExclusiveOwner?
    /// Whether the controller risks being exposed twice to apps.
    let duplicateExposureRisk: String
    /// Who serves the model: the `server` setting, or `ojd` for a controller the system cannot
    /// serve.
    let server: ControllerServer
    /// The record layer that sets `server`: `Bundled`, `Package`, or `User`; `Default` when no
    /// layer sets it; `Route` when the system cannot serve the controller.
    let serverSource: String
  }

  /// Whether input reports arrive.
  struct InputHealth: Encodable, Equatable {
    /// The health state of the input.
    let state: String
    /// The report format that the input uses, when known.
    let reportFormat: String?
    /// Why the input failed, when it did.
    let failureReason: String?
    /// How many times the service recovered the input.
    let recoveryCount: Int
  }

  /// What the controller can read and do.
  struct Capabilities: Encodable, Equatable {
    /// The controls the controller has.
    let controls: [String]
    /// How many touch contacts the controller reports.
    let touchContactCount: Int
    /// Whether the controller has motion sensors.
    let motion: Bool
    /// The rumble motors that take an intensity.
    let rumbleMotors: [String]
    /// The rumble motors that only switch on and off.
    let binaryRumbleMotors: [String]
    /// The lighting features the controller has.
    let lightingFeatures: [String]
    /// The adaptive triggers the controller has.
    let adaptiveTriggers: [String]
    /// `macos` when macOS serves the controller natively, so the output lists above hold only what
    /// macOS leaves undone; `ojd` when OJD drives all of the controller's output.
    let outputOwner: String
  }

  /// The record's `tuning` as applied, named as in the record file; a value the record does not
  /// set is absent.
  struct Tuning: Encodable, Equatable {
    /// The radial dead zone of both sticks on the virtual gamepad, as a fraction of full
    /// deflection.
    let stickDeadzone: Float?
    /// How long the controller can send no input before OJD releases its held controls, in
    /// milliseconds.
    let inputLivenessTimeoutMs: Int?
    /// The gap between the HID startup writes, in milliseconds.
    let hidStartupIntervalMs: Int?
    /// The shortest gap between rumble and lighting reports, in milliseconds.
    let minimumHIDOutputIntervalMs: Int?
    /// The gap between HID startup recovery rounds, in milliseconds.
    let hidStartupRecoveryIntervalMs: Int?
    /// The HID startup recovery rounds before OJD gives up.
    let hidStartupRecoveryRounds: Int?
    /// The keep-alive ticks between resends of the lizard-mode-off request.
    let lizardResendTicks: Int?
    /// The timeout of one USB command transfer, in milliseconds.
    let usbCommandTimeoutMs: Int?
    /// The input reports between resends of the request that makes a controller announce itself.
    let presenceResendReports: Int?
    /// How long an adapter or dongle can stay silent before its controller counts as
    /// disconnected, in milliseconds.
    let adapterDisconnectDelayMs: Int?
    /// The gap between the raw-USB startup writes, in milliseconds.
    let usbStartupIntervalMs: Int?
    /// The wait before the first USB startup retry, in milliseconds; each later retry waits
    /// twice as long.
    let usbStartupRetryDelayMs: Int?
    /// The timeout of each raw-USB transfer, in milliseconds.
    let usbTransferTimeoutMs: Int?
    /// How many virtual gamepad reports may wait behind the one being sent.
    let frameQueueCapacity: Int?

    /// Creates the tuning from `tuning`; nil when the record sets no tuning.
    init?(_ tuning: ControllerTuning) {
      guard tuning != .none else { return nil }
      stickDeadzone = tuning.stickDeadzone
      inputLivenessTimeoutMs = tuning.inputLivenessTimeoutMilliseconds
      hidStartupIntervalMs = tuning.hidStartupIntervalMilliseconds
      minimumHIDOutputIntervalMs = tuning.minimumHIDOutputIntervalMilliseconds
      hidStartupRecoveryIntervalMs = tuning.hidStartupRecoveryIntervalMilliseconds
      hidStartupRecoveryRounds = tuning.hidStartupRecoveryRounds
      lizardResendTicks = tuning.lizardResendTicks
      usbCommandTimeoutMs = tuning.usbCommandTimeoutMilliseconds
      presenceResendReports = tuning.presenceResendReports
      adapterDisconnectDelayMs = tuning.adapterDisconnectDelayMilliseconds
      usbStartupIntervalMs = tuning.usbStartupIntervalMilliseconds
      usbStartupRetryDelayMs = tuning.usbStartupRetryDelayMilliseconds
      usbTransferTimeoutMs = tuning.usbTransferTimeoutMilliseconds
      frameQueueCapacity = tuning.frameQueueCapacity
    }

    /// The set values as `name=value`, in record-file order.
    var rows: [String] {
      [
        stickDeadzone.map { "stickDeadzone=\($0)" },
        inputLivenessTimeoutMs.map { "inputLivenessTimeoutMs=\($0)" },
        hidStartupIntervalMs.map { "hidStartupIntervalMs=\($0)" },
        minimumHIDOutputIntervalMs.map { "minimumHIDOutputIntervalMs=\($0)" },
        hidStartupRecoveryIntervalMs.map { "hidStartupRecoveryIntervalMs=\($0)" },
        hidStartupRecoveryRounds.map { "hidStartupRecoveryRounds=\($0)" },
        lizardResendTicks.map { "lizardResendTicks=\($0)" },
        usbCommandTimeoutMs.map { "usbCommandTimeoutMs=\($0)" },
        presenceResendReports.map { "presenceResendReports=\($0)" },
        adapterDisconnectDelayMs.map { "adapterDisconnectDelayMs=\($0)" },
        usbStartupIntervalMs.map { "usbStartupIntervalMs=\($0)" },
        usbStartupRetryDelayMs.map { "usbStartupRetryDelayMs=\($0)" },
        usbTransferTimeoutMs.map { "usbTransferTimeoutMs=\($0)" },
        frameQueueCapacity.map { "frameQueueCapacity=\($0)" },
      ].compactMap { $0 }
    }
  }

  /// The virtual gamepad of the controller.
  struct Virtual: Encodable, Equatable {
    /// The ID of the virtual gamepad profile that serves the controller.
    let profile: String?
    /// Where the profile choice comes from.
    let source: VirtualHIDProfileSource?
    /// The profile that a stored choice names.
    let override: String?
    /// `Unit` or `Model`: which choice `override` is.
    let overrideScope: VirtualHIDProfileOverrideScope?
    /// Whether the controller has no virtual gamepad profile to publish.
    let unavailable: Bool
  }

  /// How OJD serves the controller, as `ServingPolicy` decides it.
  struct Serving: Encodable, Equatable {
    /// The route: `NativePassThrough`, `VirtualHID`, `ExtensionOwned` or `OutputDisabled`.
    let route: String
    /// The persona OJD publishes; absent for a route that publishes nothing.
    let persona: String?
    /// Why a route publishes nothing; absent for a route that serves.
    let reason: String?

    /// Creates the description from the serving decision.
    init(_ decision: ServingDecision) {
      route = decision.route.id
      persona = decision.selection?.profileID.rawValue
      reason = decision.route.disabledReason?.rawValue
    }
  }

  /// Whether a virtual device publishes the controller, and why not.
  struct Publication: Encodable, Equatable {
    /// The publication state.
    let state: String
    /// Set exactly when `state` is `NotPublished`.
    let reason: String?
    /// Set exactly when `state` is `Failed`.
    let failure: String?
    /// The backend that publishes the controller.
    let target: String?
    /// System uptime in nanoseconds of the last send to the virtual device.
    let lastAttemptedNanoseconds: UInt64?
    /// System uptime in nanoseconds of the last send the virtual device accepted.
    let lastCompletedNanoseconds: UInt64?
  }

  /// The effective record for the controller's model, in the layer and file shape of `record list`.
  struct Record: Encodable, Equatable {
    /// The record layer: `Bundled`, `Package` or `User`.
    let layer: String
    /// The record file, when the record comes from a file.
    let file: String?

    /// Creates the description from `record`.
    init(_ record: ControllerRecord) {
      layer = record.layer.rawValue
      file = record.file?.path
    }
  }

  /// A check of one output command and the observation that shows it worked.
  struct OutputCheck: Encodable, Equatable {
    /// The ID of the check.
    let id: String
    /// The `ojd` command that runs the check.
    let command: String
    /// What the user should observe.
    let expected: String
  }

  /// The controller in `controller show`.
  struct Detail: Encodable, Equatable {
    /// The session ID.
    let id: String
    /// The unit ID, when the controller has one.
    let unit: String?
    /// The controller name.
    let name: String
    /// The USB vendor ID.
    let vendorID: Int
    /// The USB product ID.
    let productID: Int
    /// How the controller connects.
    let connection: String
    /// Encoded as the binding's document value, such as `XboxXUSB:Receiver`.
    let `protocol`: ProtocolBindingID
    /// The USB interface number, when the controller reports one.
    let interfaceNumber: Int?
    /// Whether the controller reports a serial number; the number itself is not shown.
    let hasSerialNumber: Bool
    /// The session state, such as active or suspended.
    let session: String
    /// Absent when the service reports no power state.
    let power: ControllerConnectionState.Power?
    /// The status of the startup commands, when the controller takes any.
    let startupCommandStatus: String?
    /// The health of the input.
    let inputHealth: InputHealth
    /// Who owns and serves the controller.
    let ownership: Ownership
    /// How OJD serves the controller.
    let serving: Serving
    /// The protocol parameters of the controller.
    let parameters: [String]
    /// The effective record of the model, when one exists.
    let record: Record?
    /// Where the HID usage map comes from; absent unless the `HIDDescriptor` protocol drives the
    /// controller.
    let inputMapping: InputMapping?
    /// Absent when the controller's record sets no tuning.
    let tuning: Tuning?
    /// What the controller can read and do.
    let capabilities: Capabilities
    /// The virtual gamepad of the controller, when the service reports one.
    let virtual: Virtual?
    /// Whether a virtual device publishes the controller, when the service reports it.
    let publication: Publication?
    /// The checks that test the controller's outputs.
    let outputChecks: [OutputCheck]
  }

  /// The controller that the report describes.
  let controller: Detail

  /// Encodes the fields of `controller` at the top level; the document is the controller.
  func encode(to encoder: any Encoder) throws {
    try controller.encode(to: encoder)
  }

  /// Describes `device`.
  ///
  /// - Parameters:
  ///   - device: The description of the controller.
  ///   - record: The effective record of the device's model, if there is one.
  ///   - sharesModel: Whether another connected controller has the same VID:PID, so the output
  ///     checks must name this one by its ID.
  init(
    _ device: ApplicationServiceDeviceDescription,
    record: ControllerRecord?,
    sharesModel: Bool = false
  ) {
    let output = device.physicalOutputCapabilities
    let offersServerChoice = ServingPolicy.offersServerChoice(ServingInput(device))
    controller = Detail(
      id: device.sessionToken.rawValue,
      unit: device.portKey?.rawValue,
      name: device.name,
      vendorID: Int(device.vendorID),
      productID: Int(device.productID),
      connection: device.connection,
      protocol: device.protocolBinding,
      interfaceNumber: device.interfaceNumber.map(Int.init),
      hasSerialNumber: device.serialNumber.map { !$0.isEmpty } ?? false,
      session: device.sessionState.rawValue,
      power: device.connectionState?.power,
      startupCommandStatus: device.startupCommandStatus,
      inputHealth: InputHealth(
        state: device.inputHealth.state.rawValue,
        reportFormat: device.inputHealth.reportFormat,
        failureReason: device.inputHealth.failureReason?.rawValue,
        recoveryCount: device.inputHealth.recoveryCount
      ),
      ownership: Ownership(
        discoverySource: device.discoverySource.rawValue,
        physical: device.physicalOwnership.rawValue,
        hidInput: device.hidInputOwnership.rawValue,
        owner: device.inputOwner,
        duplicateExposureRisk: device.duplicateExposureRisk.rawValue,
        server: offersServerChoice ? record?.server ?? .system : .ojd,
        serverSource: offersServerChoice
          ? record?.serverSource ?? ControllerRecord.defaultServerSource
          : ControllerRecord.routeServerSource
      ),
      serving: Serving(device.servingDecision),
      parameters: device.parameters,
      record: record.map(Record.init),
      inputMapping: device.bindingResult.inputMapping,
      tuning: Tuning(device.tuning),
      capabilities: Capabilities(
        controls: Control.allCases.filter(device.capabilities.controls.contains).map(\.rawValue),
        touchContactCount: Int(device.capabilities.touchContactCount),
        motion: device.capabilities.motion,
        rumbleMotors: output.rumbleMotors.map(\.rawValue),
        binaryRumbleMotors: output.binaryRumbleMotors.map(\.rawValue),
        lightingFeatures: output.lightingFeatures.map(\.rawValue),
        adaptiveTriggers: output.adaptiveTriggers.map(\.rawValue),
        outputOwner: device.physicalOutputOwner.rawValue
      ),
      virtual: device.virtualHIDProfile.map {
        Virtual(
          profile: device.servingDecision.selection?.profileID.rawValue,
          source: device.servingDecision.selection?.source.reported,
          override: $0.override?.rawValue,
          overrideScope: $0.overrideScope,
          unavailable: device.servingDecision.route == .outputDisabled(.noVirtualProfile)
        )
      },
      publication: device.publication.map {
        Publication(
          state: $0.state.rawValue,
          reason: $0.reason?.rawValue,
          failure: $0.failure,
          target: $0.target?.rawValue,
          lastAttemptedNanoseconds: $0.lastAttemptedNanoseconds,
          lastCompletedNanoseconds: $0.lastCompletedNanoseconds
        )
      },
      outputChecks: PhysicalOutputValidationPlan(
        device: device,
        selector: sharesModel ? device.sessionToken.rawValue : nil
      ).steps.map {
        OutputCheck(id: $0.id, command: $0.command, expected: $0.expectedObservation)
      }
    )
  }
}

extension InputMapping {
  /// The `--plain` fields: source, match tier, GUID and the unmapped controls; empty when absent.
  var plainFields: [String] {
    [
      CommandLineName.kebab(source.rawValue), match.map { CommandLineName.kebab($0.rawValue) } ?? "",
      guid ?? "", unmapped.joined(separator: ","),
    ]
  }
}
