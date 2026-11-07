import Foundation
import OpenJoystickDriverKit

/// The `ojd status --json` result.
///
/// Keys and enum values are stable identifiers. Fields that only the service can report are absent
/// while it is stopped.
struct StatusReport: Encodable, Equatable {
  /// Why the stopped service's request listener stopped, from the record that the service leaves
  /// beside its socket.
  struct ListenerFailure: Encodable, Equatable {
    /// The failure code.
    let code: String
    /// The error number of the failure.
    let errorNumber: Int
    /// When the failure happened, in ISO 8601.
    let time: String
    /// The code with its localized text, the error number and the time.
    let message: String
    /// True while the process that recorded the failure runs; false when the service is not running
    /// and the failure is the reason its last listener stopped.
    let current: Bool

    /// The JSON keys; `errorNumber` is written `errno`.
    enum CodingKeys: String, CodingKey {
      /// The JSON key of `code`.
      case code
      /// The JSON key of `errorNumber`, written `errno`.
      case errorNumber = "errno"
      /// The JSON key of `time`.
      case time
      /// The JSON key of `message`.
      case message
      /// The JSON key of `current`.
      case current
    }

    /// Creates the entry from a recorded failure; `current` tells whether the failing process still
    /// runs.
    init(_ failure: ServiceListenerFailure, current: Bool) {
      self.current = current
      code = failure.code.rawValue
      errorNumber = Int(failure.errorNumber)
      time = failure.time.formatted(Date.ISO8601FormatStyle())
      message = current ? failure.localizedSummary : failure.localizedEarlierSummary
    }
  }

  /// The state of the service.
  struct Service: Encodable, Equatable {
    /// Whether the service runs.
    let state: ServiceStateResult.State
    /// The service version, while it runs.
    let version: String?
    /// Present while the service is stopped and left a record of its listener failure.
    let listenerFailure: ListenerFailure?
    /// Present while the service is stopped and the record cannot be used: the localized problem.
    let listenerFailureProblem: String?

    /// Creates the entry from the service state, its version and the reading of its listener
    /// failure record.
    init(
      state: ServiceStateResult.State,
      version: String?,
      listenerFailure: ServiceListenerFailure.Reading
    ) {
      self.state = state
      self.version = version
      switch listenerFailure {
      case .absent:
        self.listenerFailure = nil
        listenerFailureProblem = nil
      case .stopped(let failure):
        self.listenerFailure = ListenerFailure(failure, current: true)
        listenerFailureProblem = nil
      case .earlier(let failure):
        self.listenerFailure = ListenerFailure(failure, current: false)
        listenerFailureProblem = nil
      case .unreadable(let problem):
        self.listenerFailure = nil
        listenerFailureProblem = problem.localizedDescription
      }
    }
  }

  /// The state of the DriverKit transport extension, which `ojd` reads without the service.
  struct Extension: Encodable, Equatable {
    /// Whether the extension is in the app bundle.
    enum Bundle: String, Encodable {
      /// The extension is in the app bundle.
      case present = "Present"
      /// The extension is not in the app bundle.
      case missing = "Missing"
      /// The extension in the app bundle is not valid.
      case invalid = "Invalid"
    }

    /// Whether macOS has the extension registered.
    enum Registration: String, Encodable {
      /// The extension is registered and active.
      case active = "Active"
      /// The extension is registered and inactive.
      case inactive = "Inactive"
      /// The extension is not registered.
      case absent = "Absent"
      /// macOS cannot report the registration.
      case unavailable = "Unavailable"
    }

    /// The state of the extension in the app bundle.
    let bundle: Bundle
    /// The state of the extension in macOS.
    let registration: Registration

    /// Creates the entry from the extension status.
    init(_ status: ExtensionStatus) {
      switch status.bundle {
      case .present: bundle = .present
      case .missing: bundle = .missing
      case .invalid: bundle = .invalid
      }
      switch status.registration {
      case .active: registration = .active
      case .inactive: registration = .inactive
      case .absent: registration = .absent
      case .unavailable: registration = .unavailable
      }
    }
  }

  /// The `ojd` link the app installs, reported without the service, like the extension.
  struct CommandLineTool: Encodable, Equatable {
    /// The state of the link.
    let state: CommandLineToolLinkStatus.State
    /// The path of the link.
    let path: String
    /// The path that the link points to, when it exists.
    let target: String?

    /// Creates the entry from the link status.
    init(_ status: CommandLineToolLinkStatus) {
      state = status.state
      path = status.path
      target = status.target
    }
  }

  /// The input permissions the service holds.
  struct Permissions: Encodable, Equatable {
    /// The state of the permission to read input.
    let inputRead: PermissionManager.AccessState
    /// The state of the permission to inject input.
    let inputInject: PermissionManager.AccessState
  }

  /// The state of the virtual gamepad backend.
  struct VirtualDevice: Encodable, Equatable {
    /// Whether the virtual gamepad is on.
    let enabled: Bool?
    /// The backend's diagnostic text, with each controller's generations and send times.
    let status: String?
    /// The error of the virtual HID profile override, when there is one.
    let overrideError: String?
    /// The `id` of each connected controller that a virtual gamepad publishes.
    let published: [String]
  }

  /// A connected controller.
  struct Controller: Encodable, Equatable {
    /// The session token of the controller.
    let id: String
    /// The controller name.
    let name: String
    /// The USB vendor ID.
    let vendorID: Int
    /// The USB product ID.
    let productID: Int
    /// How the controller connects.
    let connection: String
    /// Whether a `Pause` has the controller pass through unmapped.
    let paused: Bool
    /// Where the HID usage map comes from; absent unless the `HIDDescriptor` protocol drives the
    /// controller.
    let inputMapping: InputMapping?
  }

  /// A device that OJD sees but does not map to a controller.
  struct Device: Encodable, Equatable {
    /// The USB vendor ID.
    let vendorID: Int
    /// The USB product ID.
    let productID: Int
    /// How the device connects.
    let connection: String
    /// Why the device has no binding; absent for a device that passes through.
    let reason: String?
    /// The SDL_GameControllerDB line found for a HID pad that fails the descriptor contract; absent
    /// when none was.
    let inputMapping: InputMapping?
  }

  /// The state of the service.
  let service: Service
  /// The state of the DriverKit transport extension.
  let transportExtension: Extension
  /// The state of the `ojd` link.
  let commandLineTool: CommandLineTool
  /// The input permissions; absent while the service is stopped.
  let permissions: Permissions?
  /// The virtual gamepad backend; absent while the service is stopped.
  let virtualDevice: VirtualDevice?
  /// The connected controllers; absent while the service is stopped.
  let controllers: [Controller]?
  /// The devices without a binding; absent while the service is stopped.
  let unboundDevices: [Device]?
  /// The pass-through devices; absent while the service is stopped.
  let passThroughDevices: [Device]?
  /// User controller records OJD skipped.
  ///
  /// Read from the files, so present while the service is stopped.
  let skippedRecords: [SkippedRecord]
  /// The `all.patch.json` OJD ignored whole; absent when it applied the file or there is none.
  let ignoredDefaults: SkippedRecord?
  /// Virtual device files OJD skipped, and a `Personas` folder it does not read.
  ///
  /// Read from the files, so present while the service is stopped.
  let skippedVirtualDevices: [SkippedRecord]

  /// Creates the report from the service payload, which is nil while the service is stopped, and
  /// from the states that `ojd` reads without the service.
  init(
    payload: ApplicationServiceStatusPayload?,
    extensionStatus: ExtensionStatus,
    commandLineTool: CommandLineToolLinkStatus,
    skippedRecords: [SkippedRecord] = [],
    ignoredDefaults: SkippedRecord? = nil,
    skippedVirtualDevices: [SkippedRecord] = [],
    listenerFailure: ServiceListenerFailure.Reading
  ) {
    self.transportExtension = Extension(extensionStatus)
    self.commandLineTool = CommandLineTool(commandLineTool)
    self.skippedRecords = skippedRecords
    self.ignoredDefaults = ignoredDefaults
    self.skippedVirtualDevices = skippedVirtualDevices
    guard let payload else {
      service = Service(state: .stopped, version: nil, listenerFailure: listenerFailure)
      permissions = nil
      virtualDevice = nil
      controllers = nil
      unboundDevices = nil
      passThroughDevices = nil
      return
    }
    service = Service(
      state: .running,
      version: payload.buildIdentity.semanticVersion,
      listenerFailure: .absent
    )
    permissions = Permissions(
      inputRead: payload.inputRead,
      inputInject: payload.inputInject
    )
    virtualDevice = VirtualDevice(
      enabled: payload.userSpaceVirtualDeviceEnabled,
      status: payload.userSpaceVirtualDeviceStatus?.wireValue,
      overrideError: payload.virtualHIDProfileOverrideError,
      published: payload.connectedDevices.filter { $0.publication?.state == .published }
        .map(\.sessionToken.rawValue)
    )
    controllers = payload.connectedDevices.map {
      Controller(
        id: $0.sessionToken.rawValue,
        name: $0.name,
        vendorID: Int($0.vendorID),
        productID: Int($0.productID),
        connection: $0.connection,
        paused: $0.paused,
        inputMapping: $0.bindingResult.inputMapping
      )
    }
    unboundDevices = payload.unboundDevices.map {
      Device(
        vendorID: Int($0.vendorID),
        productID: Int($0.productID),
        connection: $0.connection,
        reason: $0.reason.rawValue,
        inputMapping: $0.rejectedCandidates.lazy.compactMap(\.inputMapping).first
      )
    }
    passThroughDevices = payload.passThroughDevices.map {
      Device(
        vendorID: Int($0.vendorID),
        productID: Int($0.productID),
        connection: $0.connection,
        reason: nil,
        inputMapping: nil
      )
    }
  }
}

/// Returns `VVVV:PPPP`, the hex identity that `ojd` prints and accepts for a USB or Bluetooth
/// device.
func deviceIdentity(vendorID: Int, productID: Int) -> String {
  String(format: "%04X:%04X", vendorID, productID)
}
