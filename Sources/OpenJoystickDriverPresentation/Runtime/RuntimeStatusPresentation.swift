import Foundation
import OpenJoystickDriverKit

/// Whether the service data of a view has loaded.
enum RuntimeLoadState: Sendable, Equatable {
  /// The first read has not finished.
  case loading
  /// The data is loaded.
  case available
  /// The service cannot be reached; the value is the message.
  case unavailable(String)
  /// The read failed; the value is the message.
  case error(String)
}

/// How macOS answers for a permission.
enum RuntimePermissionState: String, Sendable, Equatable {
  /// The permission is granted.
  case granted
  /// The permission is denied.
  case denied
  /// The answer has not been read.
  case unknown
}

/// The Input Read and Input Inject permissions.
struct RuntimePermissionSummary: Sendable, Equatable {
  /// The Input Read permission.
  let inputRead: RuntimePermissionState
  /// The Input Inject permission.
  let inputInject: RuntimePermissionState

  /// Creates the summary from the two states.
  init(inputRead: RuntimePermissionState, inputInject: RuntimePermissionState) {
    self.inputRead = inputRead
    self.inputInject = inputInject
  }

  /// Creates the summary from the service status.
  init(status: ApplicationServiceStatusPayload) {
    self.init(
      inputRead: Self.state(for: status.inputRead),
      inputInject: Self.state(for: status.inputInject)
    )
  }

  /// Creates the summary from a permission snapshot.
  init(snapshot: PermissionManager.Snapshot) {
    self.init(
      inputRead: Self.state(for: snapshot.inputRead),
      inputInject: Self.state(for: snapshot.inputInject)
    )
  }

  /// Whether both permissions are granted.
  var isReady: Bool { inputRead == .granted && inputInject == .granted }

  /// The label of the Input Read permission.
  var inputReadLabel: String { RuntimePresentation.permissionLabel(inputRead) }

  /// The label of the Input Inject permission.
  var accessibilityLabel: String { RuntimePresentation.permissionLabel(inputInject) }

  /// Returns the state of an access state.
  static func state(for value: PermissionManager.AccessState) -> RuntimePermissionState {
    switch value {
    case .granted: return .granted
    case .denied: return .denied
    case .unknown: return .unknown
    }
  }
}

/// Whether the virtual controller output works.
enum RuntimeOutputState: String, Sendable, Equatable {
  /// The output is on and reports no error.
  case ready
  /// The output is off.
  case unavailable
  /// The output reports an error.
  case error
  /// The service does not say.
  case unknown
}

/// Whether the app is ready to turn controller input into output.
enum RuntimeReadiness: String, Sendable, Equatable {
  /// Everything is in order.
  case ready
  /// A permission, the output or the input of a controller needs attention.
  case needsAttention
  /// No controller is connected.
  case noController
}

/// What the views show of the service status: the permissions, the connected controllers, the
/// output and the readiness.
struct RuntimeStatusPresentation: Sendable, Equatable {
  /// The Input Read and Input Inject permissions.
  let permissions: RuntimePermissionSummary
  /// The connected controllers.
  let devices: [ApplicationServiceDeviceDescription]
  /// Why the stored virtual HID profile overrides cannot be read, as reported by the service.
  let virtualHIDProfileOverrideError: String?
  /// Whether the virtual controller output works.
  let outputState: RuntimeOutputState
  /// The sentence about the output, or nil while its state is unknown.
  let outputDetail: String?
  /// The state of the Post Event access, or nil while it is unread.
  let postEventAccess: RemappingPostEventAccessState?
  /// Whether the active profile needs Post Event access, or nil while that is unknown.
  let requiresPostEventAccess: Bool?
  /// Whether the app is ready to turn controller input into output.
  let readiness: RuntimeReadiness
  /// Connected devices that OJD does not serve and whose reason a person can act on.
  ///
  /// Set by `init(payload:)`; a presentation built from parts lists none.
  var unservedDevices: [RuntimeUnservedDevice] = []

  /// Creates the presentation from the service status. `postEventAccess` and
  /// `requiresPostEventAccess` come from reads of their own; nil means not read.
  init(
    payload: ApplicationServiceStatusPayload,
    postEventAccess: RemappingPostEventAccessState? = nil,
    requiresPostEventAccess: Bool? = nil
  ) {
    let permissions = RuntimePermissionSummary(status: payload)
    let outputState: RuntimeOutputState
    if payload.userSpaceVirtualDeviceStatus?.isError == true {
      outputState = .error
    } else if payload.userSpaceVirtualDeviceEnabled == nil {
      outputState = .unknown
    } else if payload.userSpaceVirtualDeviceEnabled == false {
      outputState = .unavailable
    } else {
      outputState = .ready
    }

    self.permissions = permissions
    self.devices = payload.connectedDevices
    self.unservedDevices = payload.unboundDevices.map(RuntimeUnservedDevice.init)
    self.virtualHIDProfileOverrideError = payload.virtualHIDProfileOverrideError
    self.outputState = outputState
    self.outputDetail = RuntimePresentation.outputDetail(
      enabled: payload.userSpaceVirtualDeviceEnabled,
      status: payload.userSpaceVirtualDeviceStatus
    )
    self.postEventAccess = postEventAccess
    self.requiresPostEventAccess = requiresPostEventAccess
    self.readiness = Self.readiness(
      permissions: permissions,
      outputState: outputState,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: requiresPostEventAccess,
      devices: payload.connectedDevices
    )
  }

  /// Creates the presentation from its parts.
  init(
    permissions: RuntimePermissionSummary,
    devices: [ApplicationServiceDeviceDescription],
    virtualHIDProfileOverrideError: String?,
    outputState: RuntimeOutputState,
    outputDetail: String?,
    postEventAccess: RemappingPostEventAccessState?,
    requiresPostEventAccess: Bool?,
    readiness: RuntimeReadiness
  ) {
    self.permissions = permissions
    self.devices = devices
    self.virtualHIDProfileOverrideError = virtualHIDProfileOverrideError
    self.outputState = outputState
    self.outputDetail = outputDetail
    self.postEventAccess = postEventAccess
    self.requiresPostEventAccess = requiresPostEventAccess
    self.readiness = readiness
  }
}

/// A connected device that OJD does not serve, with the sentence that says why and the one that
/// says what to do.
struct RuntimeUnservedDevice: Sendable, Equatable, Identifiable {
  /// `VVVV:PPPP`, the identity `ojd` prints.
  let identity: String
  /// How the device connects.
  let connection: String
  /// The sentence that says why OJD does not serve the device.
  let explanation: String
  /// The sentence that says what to do about it.
  let nextStep: String

  /// The identity and the connection, which together identify the entry.
  var id: String { "\(identity) \(connection)" }

  /// Creates the entry for an unbound device.
  init(_ device: ApplicationServiceUnboundDevice) {
    identity = String(format: "%04x:%04x", device.vendorID, device.productID)
    connection = device.connection
    explanation = OJDLocalized.string(device.reason.explanationKey)
    nextStep = OJDLocalized.string(device.reason.nextStepKey)
  }
}

/// The load state of the service status.
enum RuntimeStatusState: Sendable, Equatable {
  /// The first read has not finished.
  case loading
  /// The status is loaded; the value holds it.
  case available(RuntimeStatusPresentation)
  /// The service cannot be reached; the value is the message.
  case unavailable(String)
  /// The read failed; the value is the message.
  case error(String)
}

/// The load state of the profile library.
enum RuntimeRemappingState: Sendable, Equatable {
  /// The first read has not finished.
  case loading
  /// The library is loaded; the value holds its snapshot.
  case available(ApplicationServiceRemappingSnapshotPayload)
  /// The service cannot be reached; the value is the message.
  case unavailable(String)
  /// The read failed; the value is the message.
  case error(String)
}

/// The active profile of a controller as the views show it.
enum RuntimeActiveProfileState: Sendable, Equatable {
  /// The profile library has not loaded.
  case loading
  /// No profile is active.
  case noProfile
  /// A profile is active; the value is its name.
  case profile(String)
  /// The service cannot be reached; the value is the message.
  case unavailable(String)
  /// The read failed; the value is the message.
  case error(String)
}

/// The load state of the permissions.
enum RuntimePermissionLoadState: Sendable, Equatable {
  /// The first read has not finished.
  case loading
  /// The permissions cannot be read.
  case unavailable
  /// The app asks macOS for the permissions.
  case requesting
  /// The permissions are read; the value holds them.
  case available(RuntimePermissionSummary)
  /// The read failed; the value is the message.
  case error(String)
}

/// The load state of the Post Event access.
enum RuntimePostEventAccessLoadState: Sendable, Equatable {
  /// The first read has not finished.
  case loading
  /// The app asks macOS for the access.
  case requesting
  /// The access is read; the value is its state.
  case available(RemappingPostEventAccessState)
  /// The service cannot be reached; the value is the message.
  case unavailable(String)
  /// The read failed; the value is the message.
  case error(String)
}

/// A controller model: the scope of a virtual HID profile override, which the service applies to
/// every connected controller with the same vendor and product.
struct RuntimeControllerModel: Hashable, Sendable {
  /// The USB vendor ID.
  let vendorID: UInt16
  /// The USB product ID.
  let productID: UInt16

  /// Creates the model from the vendor and product IDs.
  init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  /// Creates the model of a connected controller.
  init(_ device: ApplicationServiceDeviceDescription) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }
}

/// The virtual HID profile override request and last failure of one controller model.
struct RuntimeVirtualHIDProfileOverrideState: Sendable, Equatable {
  /// A virtual HID profile override request.
  enum Request: Sendable, Equatable {
    /// Select the profile.
    case set(VirtualHIDProfileID)
    /// Return to automatic selection.
    case reset

    /// The override the request stores; nil for a reset to automatic selection.
    var requested: VirtualHIDProfileID? {
      guard case .set(let profile) = self else { return nil }
      return profile
    }
  }

  /// The request being applied, or nil when none is in flight.
  var request: Request?
  /// The message of the last failed request, or nil.
  var failure: String?

  /// Whether a request is being applied.
  var inFlight: Bool { request != nil }
}

/// Where a change of the profile library is.
enum RuntimeMutationState: Sendable {
  /// No change runs.
  case idle
  /// A change is being saved.
  case saving
  /// The change of the profile succeeded.
  case succeeded(profileID: UUID)
  /// The operation completed.
  case completed(RuntimeMutationOperation)
  /// The stored profile differs from the one the edit started from; the value is the profile, if
  /// there is one.
  case conflict(profileID: UUID?)
  /// The change failed; the value is the message.
  case error(String)
}

/// A request to change the profile library, with the identifier that ties it to its result.
struct RuntimeMutationRequest: Equatable, Sendable {
  /// The change.
  let operation: RuntimeMutationOperation
  /// The identifier of the request.
  let id: UUID

  /// Creates the request; the identifier defaults to a fresh one.
  init(operation: RuntimeMutationOperation, id: UUID = UUID()) {
    self.operation = operation
    self.id = id
  }
}

/// How a request to change the profile library ended.
enum RuntimeMutationResult: Equatable, Sendable {
  /// The change succeeded.
  case succeeded(id: UUID, operation: RuntimeMutationOperation)
  /// The stored profile differs from the one the edit started from.
  case conflict(id: UUID, operation: RuntimeMutationOperation)
  /// The change failed; the message says why.
  case failed(id: UUID, operation: RuntimeMutationOperation, message: String)
  /// The app refused the change because another action is in progress; the message says so.
  case rejected(id: UUID, operation: RuntimeMutationOperation, message: String)

  /// The identifier of the request.
  var id: UUID {
    switch self {
    case .succeeded(let id, _), .conflict(let id, _), .failed(let id, _, _),
      .rejected(let id, _, _):
      return id
    }
  }

  /// The change.
  var operation: RuntimeMutationOperation {
    switch self {
    case .succeeded(_, let operation), .conflict(_, let operation), .failed(_, let operation, _),
      .rejected(_, let operation, _):
      return operation
    }
  }

  /// The request that the result answers.
  var request: RuntimeMutationRequest { RuntimeMutationRequest(operation: operation, id: id) }
}

/// A change of the profile library.
enum RuntimeMutationOperation: Sendable, Equatable {
  /// Create a profile.
  case create(profileID: UUID)
  /// Update a profile.
  case update(profileID: UUID)
  /// Import a profile.
  case importProfile(profileID: UUID)
  /// Delete a profile.
  case delete(profileID: UUID)
  /// Activate a profile.
  case activate(profileID: UUID)
  /// Deactivate a profile by its identifier; nil deactivates the active profile of a controller
  /// model.
  case deactivate(profileID: UUID?)

  /// The profile that the change concerns, or nil.
  var profileID: UUID? {
    switch self {
    case .create(let profileID), .update(let profileID), .importProfile(let profileID),
      .delete(let profileID), .activate(let profileID):
      return profileID
    case .deactivate(let profileID): return profileID
    }
  }
}

/// The state of the capture of the control that the user presses.
enum RuntimeInputCaptureState: Sendable {
  /// No capture runs.
  case idle
  /// The capture waits for input from the controller.
  case listening(ControllerReference)
  /// The capture received an input state from the controller.
  case received(ControllerReference, ControllerState)
  /// The capture detected a source in the input state.
  case detected(ControllerReference, ControllerState, RemappingSource)
  /// The service cannot be reached; the value is the message.
  case unavailable(ControllerReference, String)
  /// The capture failed; the value is the message.
  case error(ControllerReference, String)
}
