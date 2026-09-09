import CoreHID
import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

/// Publishes one virtual gamepad for each connected physical controller.
///
/// macOS 15 and later use CoreHID. macOS 10.15 through 14 use the earlier
/// IOKit user-space HID API because CoreHID is unavailable there. Neither path
/// runs in the USB DriverKit extension.
public final class UserSpaceOutputDispatcher: CompatibilityUserSpaceOutputDispatching,
  CompatibilityUserSpaceOutputControllerActivating, @unchecked Sendable
{
  public typealias RumbleCommandHandler = @Sendable (DeviceIdentifier, VirtualRumbleCommand) -> Void

  public enum CreationError: Error, CustomStringConvertible, Sendable {
    case createFailed
    case inputMonitoringDenied
    case accessibilityDenied
    case missingEntitlement(String)
    case provisioningProfileExcludesHost

    public var description: String {
      switch self {
      case .createFailed: return "Failed to create virtual HID device"
      case .inputMonitoringDenied: return "Input Monitoring denied for IOKit virtual device"
      case .accessibilityDenied: return "Accessibility denied for IOKit virtual device"
      case .missingEntitlement(let entitlement): return "Missing entitlement: \(entitlement)"
      case .provisioningProfileExcludesHost:
        return "Development provisioning profile does not include this Mac"
      }
    }
  }

  protocol VirtualDeviceBackend: AnyObject, Sendable {
    func send(_ report: [UInt8]) async throws
    func close()
  }

  private final class LifecycleState: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    var isOpen: Bool { lock.withLock { !closed } }

    func close() -> Bool {
      lock.withLock {
        guard !closed else { return false }
        closed = true
        return true
      }
    }
  }

  private struct IOKitReportError: Error, Sendable { let code: IOReturn }

  /// Interrupt IN for IOKit clients (`hid_read`). GetReport is a separate control path.
  static func publishIOKitInputReport(_ device: IOHIDUserDevice, report: [UInt8]) throws {
    let result = report.withUnsafeBytes { pointer -> IOReturn in
      guard let base = pointer.baseAddress else { return kIOReturnBadArgument }
      return IOHIDUserDeviceHandleReportWithTimeStamp(
        device,
        mach_absolute_time(),
        base.assumingMemoryBound(to: UInt8.self),
        pointer.count
      )
    }
    guard result == kIOReturnSuccess else { throw IOKitReportError(code: result) }
  }

  @available(macOS, introduced: 10.15, obsoleted: 15.0)
  private final class IOHIDBackend: VirtualDeviceBackend, @unchecked Sendable {
    let device: IOHIDUserDevice
    let queue: DispatchQueue
    private let lock = NSLock()
    private var isClosed = false

    init(device: IOHIDUserDevice, queue: DispatchQueue) {
      self.device = device
      self.queue = queue
    }

    deinit { close() }

    func send(_ report: [UInt8]) throws {
      guard !lock.withLock({ isClosed }) else { throw CancellationError() }
      try UserSpaceOutputDispatcher.publishIOKitInputReport(device, report: report)
    }

    func close() {
      let shouldClose = lock.withLock { () -> Bool in
        guard !isClosed else { return false }
        isClosed = true
        return true
      }
      if shouldClose { IOHIDUserDeviceCancel(device) }
    }
  }

  @available(macOS 15, *)
  private final class CoreHIDBackend: VirtualDeviceBackend, @unchecked Sendable {
    let device: HIDVirtualDevice
    let delegateOwner: CoreHIDDelegate
    private let lock = NSLock()
    private var isClosed = false

    init(device: HIDVirtualDevice, delegate: CoreHIDDelegate) {
      self.device = device
      delegateOwner = delegate
    }

    func send(_ report: [UInt8]) async throws {
      guard !lock.withLock({ isClosed }) else { throw CancellationError() }
      // CoreHID GetReport is the delegate. HIDAPI `hid_read` is IOKit interrupt IN
      // via HandleReport. dispatchInputReport alone can leave that queue idle.
      if #available(macOS 26, *), let userDevice = device.hidDevice {
        try UserSpaceOutputDispatcher.publishIOKitInputReport(userDevice, report: report)
      }
      try await device.dispatchInputReport(data: Data(report), timestamp: SuspendingClock.now)
    }

    func close() { lock.withLock { isClosed = true } }
  }

  private let profile: VirtualDeviceProfile
  private let format: any VirtualGamepadReportFormat
  private let primaryUsage: Int
  let emitsXboxGuideReport: Bool
  private let productNameOverride: String?
  private let onRumbleCommand: RumbleCommandHandler?
  private let onControllerDidStop: (@Sendable (DeviceIdentifier) async -> Void)?
  private let lifecycle = LifecycleState()
  private let testBackendFactory:
    (@Sendable (DeviceIdentifier) async throws -> any VirtualDeviceBackend)?
  private let registryLock = NSLock()
  private var entries: [DeviceIdentifier: Entry] = [:]
  private var creationTasks: [DeviceIdentifier: Task<Entry, Error>] = [:]
  private var creationRetryPolicies: [DeviceIdentifier: UserSpaceDeviceCreationRetryPolicy] = [:]
  private var lifecycleGenerations: [DeviceIdentifier: UInt64] = [:]
  private var shutdownTask: Task<Void, Never>?
  private var _suppressOutput = false
  private var _status = "off"
  private var _lastRumbleStatus = "none"

  public var suppressOutput: Bool {
    get { registryLock.withLock { _suppressOutput } }
    set { registryLock.withLock { _suppressOutput = newValue } }
  }

  public var status: String { registryLock.withLock { _status } }
  public func setOutputSuppressed(_ suppressed: Bool) async {
    let senders = registryLock.withLock {
      _suppressOutput = suppressed
      return entries.values.map(\.sender)
    }
    for sender in senders { _ = await sender.submit { [] }.result }
  }
  public var lastRumbleStatus: String { registryLock.withLock { _lastRumbleStatus } }

  static let requiredVirtualDeviceEntitlement = "com.apple.developer.hid.virtual.device"
  static var hasRequiredVirtualDeviceEntitlement: Bool {
    hasEntitlement(requiredVirtualDeviceEntitlement)
  }

  @preconcurrency
  public init(
    profile: VirtualDeviceProfile = .default,
    format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat(),
    emitsXboxGuideReport: Bool = false,
    productNameOverride: String? = nil,
    onRumbleCommand: RumbleCommandHandler? = nil,
    onControllerDidStop: (@Sendable (DeviceIdentifier) async -> Void)? = nil
  ) throws {
    self.profile = profile
    self.format = format
    self.primaryUsage = Self.defaultPrimaryUsage(for: format)
    self.emitsXboxGuideReport = emitsXboxGuideReport
    self.productNameOverride = productNameOverride
    self.onRumbleCommand = onRumbleCommand
    self.onControllerDidStop = onControllerDidStop
    self.testBackendFactory = nil

    guard Self.hasRequiredVirtualDeviceEntitlement else {
      throw CreationError.missingEntitlement(Self.requiredVirtualDeviceEntitlement)
    }
  }

  init(
    testBackendFactory:
      @escaping @Sendable (DeviceIdentifier) async throws -> any VirtualDeviceBackend,
    onControllerDidStop: (@Sendable (DeviceIdentifier) async -> Void)? = nil
  ) {
    profile = .default
    format = OJDGenericGamepadFormat()
    primaryUsage = Self.defaultPrimaryUsage(for: format)
    emitsXboxGuideReport = false
    productNameOverride = nil
    onRumbleCommand = nil
    self.onControllerDidStop = onControllerDidStop
    self.testBackendFactory = testBackendFactory
  }

  deinit { beginClose() }

  public func close() async { await beginClose().value }

  /// Creates and neutrally activates one virtual device for each supplied controller.
  public func activate(for identifiers: [DeviceIdentifier]) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    var seen = Set<DeviceIdentifier>()
    let identifiers = identifiers.filter { seen.insert($0).inserted }
    do {
      for identifier in identifiers {
        let entry = try await entry(for: identifier)
        guard lifecycle.isOpen else { throw CancellationError() }
        try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }.value
        startInputReportKeepalive(entry)
      }
      registryLock.withLock { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  public func activate(controller identifier: DeviceIdentifier) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    do {
      let entry = try await entry(for: identifier)
      guard lifecycle.isOpen else { throw CancellationError() }
      try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }.value
      startInputReportKeepalive(entry)
      registryLock.withLock { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  @discardableResult
  func beginClose() -> Task<Void, Never> {
    registryLock.withLock {
      if let shutdownTask { return shutdownTask }
      _ = lifecycle.close()
      let resources = Array(entries.values)
      let identifiers = Set(entries.keys).union(creationTasks.keys)
      let tasks = Array(creationTasks.values)
      entries.removeAll()
      for identifier in identifiers { lifecycleGenerations[identifier, default: 0] &+= 1 }
      creationTasks.removeAll()
      creationRetryPolicies.removeAll()
      _status = "off"
      tasks.forEach { $0.cancel() }
      let drains = resources.map { $0.beginClose() }
      let shutdown = Task {
        for drain in drains { await drain.value }
        for task in tasks { if let entry = try? await task.value { await entry.close() } }
      }
      shutdownTask = shutdown
      return shutdown
    }
  }

  private func startInputReportKeepalive(_ entry: Entry) {
    entry.startInputReportKeepalive { [weak self] in
      guard let self else { return false }
      return self.lifecycle.isOpen && !self.suppressOutput
    }
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard lifecycle.isOpen, !suppressOutput else { return }

    let activeEntry: Entry
    do { activeEntry = try await entry(for: identifier) } catch is CancellationError {
      return
    } catch {
      registryLock.withLock { _status = "error: \(error)" }
      return
    }

    guard lifecycle.isOpen else { return }

    let stickTransfer = Self.stickTransfer(for: identifier)
    let isActive: @Sendable () -> Bool = { [self] in lifecycle.isOpen && !suppressOutput }
    do {
      try await activeEntry.sender.submit(whileActive: isActive) { [self, activeEntry] in
        guard lifecycle.isOpen, !suppressOutput else { return [] }
        let primaryReport = activeEntry.inputReportState.update { state in
          for event in events { applyEvent(event, stickTransfer: stickTransfer, state: &state) }
        }
        let secondaryReports =
          emitsXboxGuideReport ? events.compactMap { xboxGuideReport(for: $0) } : []
        return [primaryReport] + secondaryReports
      }.value
      startInputReportKeepalive(activeEntry)
      registryLock.withLock { recomputeStatusLocked() }
    } catch {
      let removed = registryLock.withLock { () -> Entry? in
        guard entries[identifier] === activeEntry else { return nil }
        _status = "error: \(error)"
        return entries.removeValue(forKey: identifier)
      }
      await removed?.close()
    }
  }

  private func entry(for identifier: DeviceIdentifier) async throws -> Entry {
    let result: (task: Task<Entry, Error>, generation: UInt64) = try registryLock.withLock {
      guard lifecycle.isOpen else { throw CancellationError() }
      let generation = lifecycleGenerations[identifier, default: 0]
      if let entry = entries[identifier] { return (Task { entry }, generation) }
      if let task = creationTasks[identifier] { return (task, generation) }

      let now = DispatchTime.now().uptimeNanoseconds
      let retryPolicy = creationRetryPolicies[identifier] ?? UserSpaceDeviceCreationRetryPolicy()
      guard retryPolicy.permitsAttempt(at: now) else { throw CreationError.createFailed }

      let task = Task { try await self.createEntry(for: identifier) }
      creationTasks[identifier] = task
      return (task, generation)
    }
    let (task, generation) = result

    do {
      let entry = try await task.value
      let installed = registryLock.withLock { () -> Bool in
        guard lifecycle.isOpen, lifecycleGenerations[identifier, default: 0] == generation else {
          return false
        }
        creationTasks.removeValue(forKey: identifier)
        creationRetryPolicies.removeValue(forKey: identifier)
        entries[identifier] = entry
        recomputeStatusLocked()
        return true
      }
      guard installed else {
        await entry.close()
        throw CancellationError()
      }
      return entry
    } catch {
      registryLock.withLock {
        guard lifecycleGenerations[identifier, default: 0] == generation else { return }
        creationTasks.removeValue(forKey: identifier)
        var policy = creationRetryPolicies[identifier] ?? UserSpaceDeviceCreationRetryPolicy()
        policy.recordFailure(at: DispatchTime.now().uptimeNanoseconds)
        creationRetryPolicies[identifier] = policy
      }
      throw error
    }
  }

  private func createEntry(for identifier: DeviceIdentifier) async throws -> Entry {
    guard lifecycle.isOpen else { throw CancellationError() }
    if let testBackendFactory {
      let backend = try await testBackendFactory(identifier)
      guard lifecycle.isOpen else {
        backend.close()
        throw CancellationError()
      }
      return Entry(backend: backend, inputReportState: UserSpaceInputReportState(format: format))
    }
    if #available(macOS 15, *) { return try await createCoreHIDEntry(for: identifier) }
    return try createIOKitEntry(for: identifier)
  }

  @available(macOS 15, *)
  private func createCoreHIDEntry(for identifier: DeviceIdentifier) async throws -> Entry {
    let properties = Self.virtualDeviceProperties(
      profile: profile,
      format: format,
      identifier: identifier,
      productNameOverride: productNameOverride
    )
    guard let device = HIDVirtualDevice(properties: properties) else {
      let error = Self.coreHIDCreationFailure()
      print("[UserSpaceOutputDispatcher] CoreHID HIDVirtualDevice create returned nil: \(error)")
      throw error
    }
    Self.applyPublishedIOHIDTransport(Self.ioHIDTransportValue(for: profile), to: device)
    let inputReportState = UserSpaceInputReportState(format: format)
    let sender = UserSpaceReportSender()
    let delegate = CoreHIDDelegate(
      handler: hostReportHandler(identifier: identifier, input: inputReportState, sender: sender)
    )
    let entry = Entry(
      backend: CoreHIDBackend(device: device, delegate: delegate),
      inputReportState: inputReportState,
      sender: sender
    )
    guard lifecycle.isOpen else {
      await entry.close()
      throw CancellationError()
    }
    await device.activate(delegate: delegate)
    guard lifecycle.isOpen else {
      await entry.close()
      throw CancellationError()
    }
    Self.applyPublishedIOHIDTransport(Self.ioHIDTransportValue(for: profile), to: device)
    print("[UserSpaceOutputDispatcher] Created CoreHID virtual device for \(identifier)")
    return entry
  }

  private func hostReportHandler(
    identifier: DeviceIdentifier,
    input: UserSpaceInputReportState,
    sender: UserSpaceReportSender
  ) -> UserSpaceHostReportHandler {
    let isOpen: @Sendable () -> Bool = { [lifecycle] in lifecycle.isOpen }
    return UserSpaceHostReportHandler(
      identifier: identifier,
      input: input,
      sender: sender,
      isOpen: isOpen,
      onRumble: onRumbleCommand
    ) { [weak self] status in self?.registryLock.withLock { self?._lastRumbleStatus = status } }
  }

  @available(macOS, introduced: 10.15, obsoleted: 15.0)
  private func createIOKitEntry(for identifier: DeviceIdentifier) throws -> Entry {
    guard PermissionManager.currentInputMonitoringAccessState() == .granted else {
      throw CreationError.inputMonitoringDenied
    }
    guard PermissionManager.currentAccessibilityAccessState() == .granted else {
      throw CreationError.accessibilityDenied
    }

    let baseProperties = Self.deviceProperties(
      profile: profile,
      format: format,
      identifier: identifier,
      productNameOverride: productNameOverride
    )
    let attempts = Self.deviceCreationAttempts(
      baseProperties: baseProperties,
      primaryUsage: primaryUsage
    )
    let candidateLocationIDs: [UInt32?] = [
      UserSpaceVirtualDeviceConstants.locationID(for: identifier), 0x1000_0002, nil,
    ]

    var device: IOHIDUserDevice?
    attemptLoop: for attempt in attempts {
      for locationID in candidateLocationIDs {
        var properties = attempt.properties
        if let locationID {
          properties[kIOHIDLocationIDKey as String] = Int64(locationID)
        } else {
          properties.removeValue(forKey: kIOHIDLocationIDKey as String)
        }
        device = IOHIDUserDeviceCreateWithProperties(
          kCFAllocatorDefault,
          properties as CFDictionary,
          attempt.options
        )
        if device != nil { break attemptLoop }
      }
    }
    guard let device else { throw CreationError.createFailed }
    guard lifecycle.isOpen else {
      IOHIDUserDeviceCancel(device)
      throw CancellationError()
    }

    let queue = DispatchQueue(
      label: "com.openjoystickdriver.iokit-hid.\(identifier.vendorID).\(identifier.productID)"
    )
    let inputReportState = UserSpaceInputReportState(format: format)
    let entry = Entry(
      backend: IOHIDBackend(device: device, queue: queue),
      inputReportState: inputReportState
    )
    let handler = hostReportHandler(
      identifier: identifier,
      input: inputReportState,
      sender: entry.sender
    )
    IOHIDUserDeviceRegisterGetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard let identifier = UInt32(exactly: reportID) else {
          throw VirtualHostReportError.malformed
        }
        let bytes = try handler.getReport(
          type: UserSpaceHostReportHandler.reportType(type),
          reportID: identifier,
          maxSize: Int(reportLength.pointee)
        )
        for (index, byte) in bytes.enumerated() { report[index] = byte }
        reportLength.pointee = bytes.count
        return kIOReturnSuccess
      } catch {
        reportLength.pointee = 0
        return UserSpaceHostReportHandler.ioKitError(error)
      }
    }
    IOHIDUserDeviceRegisterSetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard reportLength >= 0 else { throw VirtualHostReportError.malformed }
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
        _ = try handler.setReport(
          type: UserSpaceHostReportHandler.reportType(type),
          reportID: reportID,
          bytes: bytes
        )
        return kIOReturnSuccess
      } catch { return UserSpaceHostReportHandler.ioKitError(error) }
    }
    IOHIDUserDeviceSetDispatchQueue(device, queue)
    IOHIDUserDeviceActivate(device)
    print("[UserSpaceOutputDispatcher] Created IOKit virtual device for \(identifier)")
    return entry
  }

  /// IOHID `Transport` string HIDAPI matches (`kIOHIDTransportBluetoothValue` prefix).
  ///
  /// CoreHID `HIDVirtualDevice` still stamps `Transport=Virtual` unless this value is
  /// also passed through `extraProperties` and applied on the backing `IOHIDUserDevice`.
  static func ioHIDTransportValue(for profile: VirtualDeviceProfile) -> String {
    switch profile.transport {
    case kIOHIDTransportBluetoothValue, kIOHIDTransportBluetoothLowEnergyValue:
      kIOHIDTransportBluetoothValue
    default: kIOHIDTransportUSBValue
    }
  }

  @available(macOS 15, *)
  static func hidDeviceTransport(for profile: VirtualDeviceProfile) -> HIDDeviceTransport {
    ioHIDTransportValue(for: profile) == kIOHIDTransportBluetoothValue ? .bluetooth : .usb
  }

  static func virtualDeviceExtraProperties(profile: VirtualDeviceProfile) -> [String: any AnyObject]
  { [kIOHIDTransportKey as String: ioHIDTransportValue(for: profile) as CFString] }

  @available(macOS 15, *)
  static func applyPublishedIOHIDTransport(_ value: String, to device: HIDVirtualDevice) {
    if #available(macOS 26, *), let userDevice = device.hidDevice {
      IOHIDUserDeviceSetProperty(userDevice, kIOHIDTransportKey as CFString, value as CFString)
    }
  }

  @available(macOS 15, *)
  static func virtualDeviceProperties(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    identifier: DeviceIdentifier,
    productNameOverride: String? = nil
  ) -> HIDVirtualDevice.Properties {
    HIDVirtualDevice.Properties(
      descriptor: Data(format.descriptor),
      vendorID: UInt32(profile.vendorID),
      productID: UInt32(profile.productID),
      transport: hidDeviceTransport(for: profile),
      product: productNameOverride ?? profile.productName,
      manufacturer: profile.manufacturer,
      versionNumber: UInt64(profile.versionNumber),
      serialNumber: UserSpaceVirtualDeviceConstants.serialNumber(for: identifier),
      locationID: UInt64(UserSpaceVirtualDeviceConstants.locationID(for: identifier)),
      extraProperties: virtualDeviceExtraProperties(profile: profile)
    )
  }

  static func deviceProperties(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    identifier: DeviceIdentifier,
    productNameOverride: String? = nil
  ) -> [String: Any] {
    var properties: [String: Any] = [
      kIOHIDReportDescriptorKey as String: Data(format.descriptor),
      kIOHIDVendorIDKey as String: profile.vendorID,
      kIOHIDProductIDKey as String: profile.productID,
      kIOHIDVersionNumberKey as String: profile.versionNumber,
      kIOHIDProductKey as String: productNameOverride ?? profile.productName,
      kIOHIDManufacturerKey as String: profile.manufacturer,
      kIOHIDSerialNumberKey as String: UserSpaceVirtualDeviceConstants.serialNumber(
        for: identifier
      ), kIOHIDTransportKey as String: ioHIDTransportValue(for: profile),
      kIOHIDMaxInputReportSizeKey as String: reportBufferSize(
        payloadSize: format.inputReportPayloadSize,
        reportID: format.inputReportID
      ),
    ]
    if let outputSize = format.outputReportPayloadSize {
      properties[kIOHIDMaxOutputReportSizeKey as String] = reportBufferSize(
        payloadSize: outputSize,
        reportID: format.outputReportID
      )
    }
    properties[kIOHIDLocationIDKey as String] = Int64(
      UserSpaceVirtualDeviceConstants.locationID(for: identifier)
    )
    return properties
  }

  public static func defaultPrimaryUsage(for format: any VirtualGamepadReportFormat) -> Int {
    if let xbox360 = format as? Xbox360MacHIDReportFormat { return Int(xbox360.topLevelUsage) }
    return Int(kHIDUsage_GD_GamePad)
  }

  private static func reportBufferSize(payloadSize: Int, reportID: UInt8?) -> Int {
    reportID == nil ? payloadSize : payloadSize + 1
  }

  /// Classifies a nil CoreHID `HIDVirtualDevice` (macOS 15+ wraps IOHIDUserDevice;
  /// Accessibility / PostEvent deny surfaces as `IOServiceOpen` `kIOReturnNotPermitted`).
  /// Input Monitoring / ListenEvent is not mapped: it blocks `IOHIDDeviceOpen` and
  /// `GC.supportsHIDDevice`, not virtual-device create.
  static func mappedCoreHIDCreationFailure(
    provisioning: VirtualHIDProvisioningHost.Authorization,
    accessibility: PermissionManager.AccessState
  ) -> CreationError {
    if provisioning == .excludesHost { return .provisioningProfileExcludesHost }
    if accessibility != .granted { return .accessibilityDenied }
    return .createFailed
  }

  @available(macOS 15, *)
  private static func coreHIDCreationFailure() -> CreationError {
    mappedCoreHIDCreationFailure(
      provisioning: VirtualHIDProvisioningHost.currentAuthorization(),
      accessibility: PermissionManager.currentAccessibilityAccessState()
    )
  }

  private static func hasEntitlement(_ entitlement: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil),
      CFGetTypeID(value) == CFBooleanGetTypeID()
    else { return false }
    return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
  }

  private func recomputeStatusLocked() {
    _status = entries.isEmpty ? "off" : "on (devices=\(entries.count))"
  }
}

extension UserSpaceOutputDispatcher: ControllerLifecycleListener {
  public func controllerDidStop(_ identifier: DeviceIdentifier) async {
    let resources = registryLock.withLock { () -> (Entry?, Task<Entry, Error>?) in
      lifecycleGenerations[identifier, default: 0] &+= 1
      let creationTask = creationTasks.removeValue(forKey: identifier)
      creationRetryPolicies.removeValue(forKey: identifier)
      let removed = entries.removeValue(forKey: identifier)
      recomputeStatusLocked()
      return (removed, creationTask)
    }
    await resources.0?.close()
    resources.1?.cancel()
    if let creationTask = resources.1, let entry = try? await creationTask.value {
      await entry.close()
    }
    await onControllerDidStop?(identifier)
  }
}
