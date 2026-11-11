import CryptoKit
import Foundation

/// Revocable authority for power notifications delivered by one runtime start.
///
/// A caller must invalidate the session before stopping its manager. DeviceManager checks this
/// token after the actor hop, so a queued notification from an earlier runtime cannot stop or
/// restart a later manager lifecycle.
public final class DeviceManagerSystemPowerEventSession: Sendable {
  /// Whether the session still holds authority; ``invalidate()`` clears it.
  private let active = Locked(true)

  /// Creates a session that holds authority until it is invalidated.
  public init() {}

  /// Whether the session still holds authority.
  var isActive: Bool { active.withLock { $0 } }

  /// Revokes the authority for good, so a notification that is queued under it is ignored.
  public func invalidate() { active.withLock { $0 = false } }
}

/// Marks physical output issued by controller teardown.
///
/// Once teardown starts, output guards accept only writes made inside this scope, so a request
/// already in flight cannot re-enable an output after teardown neutralized it.
enum ControllerTeardownOutput {
  /// Whether the current task runs inside the teardown output scope.
  @TaskLocal
  static var isActive = false
}

/// Returns the display name of a controller: the trimmed product name, or the vendor and product
/// IDs in hex when the name is absent or blank.
func controllerDisplayName(productName: String?, vendorID: UInt16, productID: UInt16) -> String {
  if let productName {
    let value = productName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty { return value }
  }
  return String(format: "Controller %04x:%04x", vendorID, productID)
}

/// The wait between two polls of the USB transport provider by raw-USB detection, 500 ms.
let usbDetectionPollNanoseconds: UInt64 = 500_000_000
/// The wait between two checks of the host's access state by the permission watch, 1 s.
let devicePermissionWatchNanoseconds: UInt64 = 1_000_000_000
/// The nanoseconds in one millisecond, for turning a rumble duration into a sleep.
let deviceDiscoveryNanosecondsPerMillisecond: UInt64 = 1_000_000
/// The longest rumble duration in milliseconds that a controller output request accepts, 5000.
public let maxRumbleDurationMs = 5_000
/// The USB interface class code of a vendor-specific interface, `0xFF`.
let usbVendorSpecificClass: UInt8 = 0xFF

/// Numbers the rumble stop that is scheduled for each controller, so a stop that a later request
/// replaced finds out that it is stale.
struct RumbleStopTokenRegistry {
  /// The latest generation issued for each controller.
  private var generations: [LogicalControllerID: UInt64] = [:]

  /// Issues the next generation for `identifier`, which makes every earlier one stale.
  mutating func replace(for identifier: LogicalControllerID) -> UInt64 {
    let generation = (generations[identifier] ?? 0) &+ 1
    generations[identifier] = generation
    return generation
  }

  /// Whether `generation` is the latest one issued for `identifier`.
  func isCurrent(_ generation: UInt64, for identifier: LogicalControllerID) -> Bool {
    generations[identifier] == generation
  }

  /// Forgets `identifier`, so every generation issued for it is stale.
  mutating func remove(_ identifier: LogicalControllerID) {
    generations.removeValue(forKey: identifier)
  }

  /// Forgets every controller.
  mutating func removeAll() { generations.removeAll() }
}

/// A pending initialization of one HID connection.
struct HIDDeviceInitialization {
  /// The connection that is being initialized.
  let connection: HIDDeviceConnection
  /// The task that initializes the connection.
  let task: Task<Void, Never>
}

/// Owns device detection and the device pipeline of every connected controller.
///
/// Detection runs two routes: the USB transport provider for raw interfaces, and the HID backend
/// for HID-class controllers.
public actor DeviceManager {

  /// The registry of protocol drivers and controller records that binds a discovered device.
  let protocolDriverRegistry: ProtocolDriverRegistry
  /// The dispatcher that sends HID reports for every pipeline.
  let dispatcher: any OutputDispatcher
  /// The key under which each controller's port key is computed.
  let installationKey: SymmetricKey
  /// Tracks the access that the host grants, which gates HID detection.
  let permissionManager: PermissionManager
  /// The HID backend that detects HID-class controllers and reads and writes their reports.
  let hidManager: HIDManager
  /// The provider that lists and opens raw USB services; nil disables raw-USB discovery.
  let usbTransportProvider: (any USBTransportProvider)?
  /// Disconnects a wireless controller on request; nil when no disconnector is supplied.
  let wirelessControllerDisconnector: (any WirelessControllerDisconnecting)?
  /// When the frames of every pipeline reached each stage.
  public let frameTimings = FrameTimingRecorder()
  /// The device pipeline of each bound controller.
  var pipelines: [LogicalControllerID: DevicePipeline] = [:]
  /// What the manager knows about each bound controller.
  var deviceInfos: [LogicalControllerID: DeviceInfo] = [:]
  /// The startup player indicator each native controller holds, one per controller and freed on
  /// its detach.
  var startupPlayerSlots: [LogicalControllerID: PhysicalPlayerIndicator] = [:]
  /// The raw-USB detection run; empty while it is not running.
  var detectionTasks: [Task<Void, Never>] = []
  /// The HID detection run; nil while none runs.
  var hidDetectionTask: Task<Void, Never>?
  /// The identity of the current HID detection run, which a stale run compares before it acts.
  var hidDetectionSessionID: UUID?
  /// The pending HID initializations; a later connection under the same key replaces the earlier
  /// one.
  var hidInitializationTasks: [HIDInitializationKey: HIDDeviceInitialization] = [:]
  /// The controller each bound HID protocol role serves, keyed by its connection ID; input from
  /// a role's connection routes only to it.
  var hidRoleConnections: [UUID: LogicalControllerID] = [:]
  /// The keep-alive output task of each HID controller; it ends when the pipeline reports no
  /// keep-alive interval.
  var hidPeriodicOutputTasks: [LogicalControllerID: Task<Void, Never>] = [:]
  /// One output queue per interface, for HID and raw-USB controllers alike.
  var hidOutputQueues: [LogicalControllerID: PhysicalHIDOutputSerialQueue] = [:]
  /// The last removed queue per interface; the interface's next queue starts after it drains.
  var retiredHIDOutputQueues: [LogicalControllerID: PhysicalHIDOutputSerialQueue] = [:]
  /// The task that watches the access state of the host.
  var permissionWatchTask: Task<Void, Never>?
  /// Counts lifecycle changes; a detection run that started under an earlier count stops.
  var lifecycleGeneration: UInt64 = 0
  /// Whether a stop is in progress, so detection and event handling ignore new work.
  var isStopping = false
  /// Set by `start()` and cleared by `stop()`; a wake restarts only a started manager.
  var isStarted = false
  /// Whether the system sleeps; ``start()`` waits for the wake while it is set.
  var isSystemSleeping = false
  /// Controllers the user suspended; a pipeline for one of these identities starts suspended.
  ///
  /// Resume, physical disconnect, and `stop()` remove entries; sleep keeps them.
  var suspendedControllerIdentities: Set<LogicalControllerID> = []
  /// HID connections of suspended controllers that a record reload may admit again through the HID
  /// backend; their disconnect keeps the suspension for the connection that replaces them.
  var ownershipCycledHIDConnections: Set<UUID> = []
  /// Whether the pipelines publish virtual gamepad output to applications; see
  /// ``setExternalOutputAllowed(_:)``.
  var externalOutputAllowed = true
  /// The uptime in nanoseconds of the last physical HID output of each controller, which paces
  /// output by the model's minimum interval.
  var lastPhysicalHIDOutputNanoseconds: [LogicalControllerID: UInt64] = [:]
  /// The pending task that ends the timed rumble of each controller.
  var rumbleStopTasks: [LogicalControllerID: Task<Void, Never>] = [:]
  /// The speaker playback in progress on each controller.
  var speakerTasks: [LogicalControllerID: Task<ControllerOutputResult.Outcome, Never>] = [:]
  /// The generations that tell a rumble stop task whether a later request replaced it.
  var rumbleStopTokens = RumbleStopTokenRegistry()
  /// The claims on the physical output channels of each controller.
  var physicalOutputOwnership = PhysicalOutputOwnership()
  /// Observed devices that did not bind, keyed by the connection that reported them.
  var unboundDevices: [UnboundDeviceKey: UnboundDeviceSnapshot] = [:]
  /// OJD's input claim on each rejected HID connection, keyed by connection ID.
  var unboundHIDClaims: [UUID: UnboundHIDClaim] = [:]
  /// HID connections stopped for a raw-USB pipeline of the same controller, keyed by connection
  /// ID, so they can be admitted again if that pipeline never starts a session.
  var yieldedHIDConnections: [UUID: YieldedHIDConnection] = [:]
  /// Raw-USB services left acknowledged unclaimed because a native HID controller serves the
  /// same physical controller, keyed by service with the key the service would have claimed.
  var nativeShadowedUSBServices: [ControllerConnectionAddress: LogicalControllerID] = [:]
  /// Raw-USB services left acknowledged unclaimed because the host refused to read their
  /// configuration while it reported an exclusive owner, keyed by service with that owner.
  var heldUSBServices: [ControllerConnectionAddress: String] = [:]
  /// Raw-USB services whose configuration descriptor read failed on the polls before this one,
  /// keyed by service with the number of failed polls in a row.
  var usbConfigurationReadFailures: [ControllerConnectionAddress: Int] = [:]
  /// HID connections left to macOS by native pass-through, keyed by connection ID.
  var passThroughDevices: [UUID: PassThroughHIDDevice] = [:]
  /// Models whose controller records changed, for raw-USB detection to re-admit on its next poll.
  var pendingRecordReloads: Set<ControllerModelID> = []
  /// Record reloads that wait for raw-USB detection to remove their controllers.
  var recordReloadWaiters: [CheckedContinuation<Void, Never>] = []

  /// Creates a manager that sends all output to `dispatcher`.
  ///
  /// - Parameters:
  ///   - dispatcher: Output dispatcher for sending HID reports.
  ///   - installationKey: The key under which port keys are computed.
  ///   - usbTransportProvider: Native raw-USB transport provider, or nil to disable raw USB
  ///     discovery.
  ///   - wirelessControllerDisconnector: Disconnects a wireless controller at the host's Bluetooth
  ///     stack, or nil when none is available.
  ///   - bluetoothLEHub: Switch 2 controllers connected over Bluetooth LE GATT, or nil to serve
  ///     the platform's HID devices only.
  ///   - permissionManager: Tracks the access the host grants.
  ///   - hidBackend: Builds the platform's HID backend from the driver registry's model lists.
  package init(
    dispatcher: any OutputDispatcher,
    installationKey: SymmetricKey,
    usbTransportProvider: (any USBTransportProvider)? = nil,
    wirelessControllerDisconnector: (any WirelessControllerDisconnecting)? = nil,
    bluetoothLEHub: Switch2BluetoothLEHub? = nil,
    permissionManager: PermissionManager,
    hidBackend: HIDAccessBackendFactory
  ) {
    self.dispatcher = dispatcher
    self.installationKey = installationKey
    self.usbTransportProvider =
      bluetoothLEHub.map {
        BluetoothLECompositeUSBTransportProvider(base: usbTransportProvider, hub: $0)
      } ?? usbTransportProvider
    self.wirelessControllerDisconnector = wirelessControllerDisconnector
    let registry = ProtocolDriverRegistry()
    self.protocolDriverRegistry = registry
    self.permissionManager = permissionManager
    self.hidManager = HIDManager(
      primary: hidBackend({ registry.hidModels }, { registry.hidRoleModels }),
      bluetoothLEHub: bluetoothLEHub
    )
  }

  /// Creates a manager over an already built `hidManager`.
  ///
  /// The convenience initializers of the test support target delegate here.
  init(
    dispatcher: any OutputDispatcher,
    installationKey: SymmetricKey,
    usbTransportProvider: (any USBTransportProvider)?,
    wirelessControllerDisconnector: (any WirelessControllerDisconnecting)?,
    hidManager: HIDManager,
    permissionManager: PermissionManager
  ) {
    self.dispatcher = dispatcher
    self.installationKey = installationKey
    self.usbTransportProvider = usbTransportProvider
    self.wirelessControllerDisconnector = wirelessControllerDisconnector
    self.protocolDriverRegistry = ProtocolDriverRegistry()
    self.permissionManager = permissionManager
    self.hidManager = hidManager
  }
}

/// Builds a platform HID backend from the two model lists the driver registry supplies.
package typealias HIDAccessBackendFactory =
  @Sendable (
    _ additionalProfileModels: @escaping @Sendable () -> [ControllerModelID],
    _ roleProfileModels: @escaping @Sendable () -> [ControllerModelID]
  ) -> any HIDAccessBackend

extension DeviceManager {
  /// The session state of one connected controller; output routing checks it per input report.
  public func controllerSessionState(
    for identifier: LogicalControllerID
  ) async -> ControllerSessionState? {
    guard let pipeline = pipelines[identifier], await pipeline.hasConnectedController(),
      pipelines[identifier] === pipeline
    else { return nil }
    return await pipeline.controllerSessionState()
  }
}
