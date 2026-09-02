import CoreHID
import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

/// Owns the current virtual state and the exact report exposed through both push and get-report APIs.
final class UserSpaceInputReportState: @unchecked Sendable {
  private let format: any VirtualGamepadReportFormat
  private let lock = NSLock()
  private var state = VirtualGamepadState()
  private var report: [UInt8]

  init(format: any VirtualGamepadReportFormat) {
    self.format = format
    self.report = format.buildInputReport(from: VirtualGamepadState())
  }

  func update(_ body: (inout VirtualGamepadState) -> Void) -> [UInt8] {
    lock.withLock {
      body(&state)
      report = format.buildInputReport(from: state)
      return report
    }
  }

  func currentReport() -> [UInt8] { lock.withLock { report } }
}

/// Publishes one virtual gamepad for each connected physical controller.
///
/// macOS 15 and later use CoreHID. macOS 10.15 through 14 use the earlier
/// IOKit user-space HID API because CoreHID is unavailable there. Neither path
/// runs in the USB DriverKit extension.
public final class UserSpaceOutputDispatcher: CompatibilityUserSpaceOutputDispatching,
  @unchecked Sendable
{
  public typealias RumbleCommandHandler = @Sendable (DeviceIdentifier, VirtualRumbleCommand) -> Void

  public enum CreationError: Error, CustomStringConvertible, Sendable {
    case createFailed
    case inputMonitoringDenied
    case accessibilityDenied
    case missingEntitlement(String)

    public var description: String {
      switch self {
      case .createFailed: return "Failed to create virtual HID device"
      case .inputMonitoringDenied: return "Input Monitoring denied for IOKit virtual device"
      case .accessibilityDenied: return "Accessibility denied for IOKit virtual device"
      case .missingEntitlement(let entitlement): return "Missing entitlement: \(entitlement)"
      }
    }
  }

  private protocol VirtualDeviceBackend: AnyObject, Sendable {
    func send(_ report: [UInt8]) async throws
    func close()
  }

  private struct IOKitReportError: Error, Sendable { let code: IOReturn }

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

    init(device: HIDVirtualDevice, delegate: CoreHIDDelegate) {
      self.device = device
      delegateOwner = delegate
    }

    func send(_ report: [UInt8]) async throws {
      try await device.dispatchInputReport(data: Data(report), timestamp: SuspendingClock.now)
    }

    func close() {}
  }

  @available(macOS 15, *)
  private final class CoreHIDDelegate: HIDVirtualDeviceDelegate, @unchecked Sendable {
    private enum RequestError: Error {
      case unsupportedReport
      case responseTooLarge
    }

    let identifier: DeviceIdentifier
    let format: any VirtualGamepadReportFormat
    let inputReportState: UserSpaceInputReportState
    let onRumbleCommand: RumbleCommandHandler?
    let onRumbleStatus: @Sendable (String) -> Void

    init(
      identifier: DeviceIdentifier,
      format: any VirtualGamepadReportFormat,
      inputReportState: UserSpaceInputReportState,
      onRumbleCommand: RumbleCommandHandler?,
      onRumbleStatus: @escaping @Sendable (String) -> Void
    ) {
      self.identifier = identifier
      self.format = format
      self.inputReportState = inputReportState
      self.onRumbleCommand = onRumbleCommand
      self.onRumbleStatus = onRumbleStatus
    }

    func hidVirtualDevice(
      _ device: HIDVirtualDevice,
      receivedSetReportRequestOfType type: HIDReportType,
      id: HIDReportID?,
      data: Data
    ) throws {
      guard let onRumbleCommand else { throw RequestError.unsupportedReport }
      let reportID = UInt32(id?.rawValue ?? 0)
      guard
        let command = VirtualRumbleOutputReportParser.parse(
          type: Self.ioReportType(type),
          reportID: reportID,
          bytes: Array(data)
        )
      else { throw RequestError.unsupportedReport }

      let status =
        "app report id=\(reportID) L=\(command.left) R=\(command.right) "
        + "LT=\(command.leftTrigger) RT=\(command.rightTrigger)"
      onRumbleStatus(status)
      print("[UserSpaceOutputDispatcher] App rumble report: \(identifier) \(status)")
      onRumbleCommand(identifier, command)
    }

    func hidVirtualDevice(
      _ device: HIDVirtualDevice,
      receivedGetReportRequestOfType type: HIDReportType,
      id: HIDReportID?,
      maxSize: Int
    ) throws -> Data {
      guard type == .input else { throw RequestError.unsupportedReport }
      if let expectedReportID = format.inputReportID, id?.rawValue != expectedReportID {
        throw RequestError.unsupportedReport
      }
      let report = Data(inputReportState.currentReport())
      guard report.count <= maxSize else { throw RequestError.responseTooLarge }
      return report
    }

    private static func ioReportType(_ type: HIDReportType) -> IOHIDReportType {
      switch type {
      case .input: kIOHIDReportTypeInput
      case .output: kIOHIDReportTypeOutput
      case .feature: kIOHIDReportTypeFeature
      @unknown default: kIOHIDReportTypeFeature
      }
    }
  }

  private final class Entry: @unchecked Sendable {
    let backend: any VirtualDeviceBackend
    let inputReportState: UserSpaceInputReportState

    init(backend: any VirtualDeviceBackend, inputReportState: UserSpaceInputReportState) {
      self.backend = backend
      self.inputReportState = inputReportState
    }
  }

  private let profile: VirtualDeviceProfile
  private let format: any VirtualGamepadReportFormat
  private let primaryUsage: Int
  let emitsXboxGuideReport: Bool
  private let productNameOverride: String?
  private let onRumbleCommand: RumbleCommandHandler?
  private let registryLock = NSLock()
  private var entries: [DeviceIdentifier: Entry] = [:]
  private var creationTasks: [DeviceIdentifier: Task<Entry, Error>] = [:]
  private var creationRetryPolicies: [DeviceIdentifier: UserSpaceDeviceCreationRetryPolicy] = [:]
  private var lifecycleGenerations: [DeviceIdentifier: UInt64] = [:]
  private var _suppressOutput = false
  private var _status = "off"
  private var _lastRumbleStatus = "none"

  public var suppressOutput: Bool {
    get { registryLock.withLock { _suppressOutput } }
    set { registryLock.withLock { _suppressOutput = newValue } }
  }

  public var status: String { registryLock.withLock { _status } }
  public var lastRumbleStatus: String { registryLock.withLock { _lastRumbleStatus } }

  static let requiredVirtualDeviceEntitlement = "com.apple.developer.hid.virtual.device"
  static var hasRequiredVirtualDeviceEntitlement: Bool {
    hasEntitlement(requiredVirtualDeviceEntitlement)
  }

  @preconcurrency public init(
    profile: VirtualDeviceProfile = .default,
    format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat(),
    emitsXboxGuideReport: Bool = false,
    productNameOverride: String? = nil,
    onRumbleCommand: RumbleCommandHandler? = nil
  ) throws {
    self.profile = profile
    self.format = format
    self.primaryUsage = Self.defaultPrimaryUsage(for: format)
    self.emitsXboxGuideReport = emitsXboxGuideReport
    self.productNameOverride = productNameOverride
    self.onRumbleCommand = onRumbleCommand

    guard Self.hasRequiredVirtualDeviceEntitlement else {
      throw CreationError.missingEntitlement(Self.requiredVirtualDeviceEntitlement)
    }
  }

  deinit { closeResources() }

  public func close() {
    closeResources()
  }

  private func closeResources() {
    let resources = registryLock.withLock { () -> ([Entry], [Task<Entry, Error>]) in
      let entries = Array(entries.values)
      let identifiers = Set(self.entries.keys).union(creationTasks.keys)
      self.entries.removeAll()
      let tasks = Array(creationTasks.values)
      for identifier in identifiers { lifecycleGenerations[identifier, default: 0] &+= 1 }
      creationTasks.removeAll()
      creationRetryPolicies.removeAll()
      _status = "off"
      return (entries, tasks)
    }
    resources.1.forEach { $0.cancel() }
    resources.0.forEach { $0.backend.close() }
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput else { return }

    let activeEntry: Entry
    do { activeEntry = try await entry(for: identifier) } catch is CancellationError {
      return
    } catch {
      registryLock.withLock { _status = "error: \(error)" }
      return
    }

    let primaryReport = activeEntry.inputReportState.update { state in
      for event in events { applyEvent(event, deadzone: 0.15, state: &state) }
    }
    let secondaryReports =
      emitsXboxGuideReport ? events.compactMap { xboxGuideReport(for: $0) } : []
    let reports = [primaryReport] + secondaryReports

    do {
      for report in reports { try await activeEntry.backend.send(report) }
      registryLock.withLock { recomputeStatusLocked() }
    } catch {
      let removed = registryLock.withLock { () -> Entry? in
        guard entries[identifier] === activeEntry else { return nil }
        _status = "error: \(error)"
        return entries.removeValue(forKey: identifier)
      }
      removed?.backend.close()
    }
  }

  private func entry(for identifier: DeviceIdentifier) async throws -> Entry {
    let result: (task: Task<Entry, Error>, generation: UInt64) = try registryLock.withLock {
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
        guard lifecycleGenerations[identifier, default: 0] == generation else { return false }
        creationTasks.removeValue(forKey: identifier)
        creationRetryPolicies.removeValue(forKey: identifier)
        entries[identifier] = entry
        recomputeStatusLocked()
        return true
      }
      guard installed else {
        entry.backend.close()
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
    if #available(macOS 15, *) { return try await createCoreHIDEntry(for: identifier) }
    return try createIOKitEntry(for: identifier)
  }

  @available(macOS 15, *) private func createCoreHIDEntry(for identifier: DeviceIdentifier)
    async throws -> Entry
  {
    let properties = Self.virtualDeviceProperties(
      profile: profile,
      format: format,
      identifier: identifier,
      productNameOverride: productNameOverride
    )
    guard let device = HIDVirtualDevice(properties: properties) else {
      throw CreationError.createFailed
    }
    let inputReportState = UserSpaceInputReportState(format: format)
    let delegate = CoreHIDDelegate(
      identifier: identifier,
      format: format,
      inputReportState: inputReportState,
      onRumbleCommand: onRumbleCommand
    ) { [weak self] status in self?.registryLock.withLock { self?._lastRumbleStatus = status } }
    await device.activate(delegate: delegate)
    print("[UserSpaceOutputDispatcher] Created CoreHID virtual device for \(identifier)")
    return Entry(
      backend: CoreHIDBackend(device: device, delegate: delegate),
      inputReportState: inputReportState
    )
  }

  @available(macOS, introduced: 10.15, obsoleted: 15.0) private func createIOKitEntry(
    for identifier: DeviceIdentifier
  ) throws -> Entry {
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
      UserSpaceVirtualDeviceConstants.locationID(for: identifier), 0x1000_0002, nil
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

    let queue = DispatchQueue(
      label: "com.openjoystickdriver.iokit-hid.\(identifier.vendorID).\(identifier.productID)"
    )
    let inputReportState = UserSpaceInputReportState(format: format)
    IOHIDUserDeviceRegisterGetReportBlock(device) {
      [format, inputReportState] type, reportID, report, reportLength in
      guard type == kIOHIDReportTypeInput else { return kIOReturnUnsupported }
      if let expectedReportID = format.inputReportID, reportID != expectedReportID {
        return kIOReturnUnsupported
      }
      let currentReport = inputReportState.currentReport()
      guard reportLength.pointee >= currentReport.count else {
        reportLength.pointee = CFIndex(currentReport.count)
        return kIOReturnNoSpace
      }
      for (index, byte) in currentReport.enumerated() { report[index] = byte }
      reportLength.pointee = CFIndex(currentReport.count)
      return kIOReturnSuccess
    }
    if let onRumbleCommand {
      IOHIDUserDeviceRegisterSetReportBlock(device) {
        [weak self] type, reportID, report, reportLength in
        let bytes = Array(UnsafeBufferPointer(start: report, count: max(0, Int(reportLength))))
        guard
          let command = VirtualRumbleOutputReportParser.parse(
            type: type,
            reportID: reportID,
            bytes: bytes
          )
        else { return kIOReturnUnsupported }
        let status =
          "app report id=\(reportID) L=\(command.left) R=\(command.right) "
          + "LT=\(command.leftTrigger) RT=\(command.rightTrigger)"
        self?.registryLock.withLock { self?._lastRumbleStatus = status }
        onRumbleCommand(identifier, command)
        return kIOReturnSuccess
      }
    }
    IOHIDUserDeviceSetDispatchQueue(device, queue)
    IOHIDUserDeviceActivate(device)
    print("[UserSpaceOutputDispatcher] Created IOKit virtual device for \(identifier)")
    return Entry(
      backend: IOHIDBackend(device: device, queue: queue),
      inputReportState: inputReportState
    )
  }

  @available(macOS 15, *) static func virtualDeviceProperties(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    identifier: DeviceIdentifier,
    productNameOverride: String? = nil
  ) -> HIDVirtualDevice.Properties {
    HIDVirtualDevice.Properties(
      descriptor: Data(format.descriptor),
      vendorID: UInt32(profile.vendorID),
      productID: UInt32(profile.productID),
      transport: profile.transport == "Bluetooth" ? .bluetooth : .usb,
      product: productNameOverride ?? profile.productName,
      manufacturer: profile.manufacturer,
      versionNumber: UInt64(profile.versionNumber),
      serialNumber: UserSpaceVirtualDeviceConstants.serialNumber(for: identifier),
      locationID: UInt64(UserSpaceVirtualDeviceConstants.locationID(for: identifier))
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
      ), kIOHIDTransportKey as String: profile.transport,
      kIOHIDMaxInputReportSizeKey as String: reportBufferSize(
        payloadSize: format.inputReportPayloadSize,
        reportID: format.inputReportID
      )
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
  public func controllerDidStop(_ identifier: DeviceIdentifier) {
    let removed = registryLock.withLock { () -> Entry? in
      lifecycleGenerations[identifier, default: 0] &+= 1
      creationTasks.removeValue(forKey: identifier)?.cancel()
      creationRetryPolicies.removeValue(forKey: identifier)
      let removed = entries.removeValue(forKey: identifier)
      recomputeStatusLocked()
      return removed
    }
    removed?.backend.close()
  }
}
