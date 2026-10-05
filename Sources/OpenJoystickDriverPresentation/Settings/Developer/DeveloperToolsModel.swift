#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit

  @MainActor
  final class DeveloperToolsViewModel: ObservableObject {
    enum PacketFilter: Hashable {
      case activity
      case all
    }

    enum LoadState: Equatable {
      case idle
      case loading
      case ready
      case noControllers
      case unavailable(String)
    }

    enum CaptureState: Equatable {
      case idle
      case starting
      case capturing
      case stopped
      case noPackets
      case failed(String)
    }

    typealias Sleep = @Sendable (UInt64) async throws -> Void

    @Published
    private(set) var loadState: LoadState = .idle
    @Published
    private(set) var captureState: CaptureState = .idle
    @Published
    private(set) var devices: [ApplicationServiceDeviceDescription] = []
    @Published
    private(set) var selectedDevice: ApplicationServiceDeviceDescription?

    /// Family labels of the selected controller, which name its controls.
    var selectedButtonLabels: ControllerButtonLabels {
      selectedDevice.map { ControllerButtonLabels(protocolID: $0.protocolBinding.protocolID) }
        ?? .standard
    }
    @Published
    private(set) var latestInput: ControllerState?
    @Published
    private(set) var packets: [PacketLogEntry] = []
    @Published
    private(set) var observedExtraInputs: [ControlID] = []
    @Published
    var packetFilter = PacketFilter.activity

    /// Packet filtering affects only the console; copy and export retain ``packets``.
    var displayedPackets: [PacketLogEntry] {
      switch packetFilter {
      case .activity: packets.filter { $0.classification == .activity }
      case .all: packets
      }
    }

    var hiddenIdlePacketCount: Int { packets.count - displayedPackets.count }

    var diagnosticRecipeAvailable: Bool {
      guard let device = selectedDevice else { return false }
      return ProtocolDriverRegistry().record(
        for: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
      )?.gipStartupPackets.contains(where: \.isDiagnosticRecipe) == true
    }

    private let gateway: any ApplicationServiceGateway
    private let pollIntervalNanoseconds: UInt64
    private let sleep: Sleep
    private var operationTask: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0

    var hasActiveOperation: Bool { operationTask != nil }

    init(
      gateway: any ApplicationServiceGateway,
      pollIntervalNanoseconds: UInt64 = 50_000_000,
      sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
      self.gateway = gateway
      self.pollIntervalNanoseconds = pollIntervalNanoseconds
      self.sleep = sleep
    }

    var isCapturing: Bool {
      if case .capturing = captureState { return true }
      if case .starting = captureState { return true }
      return false
    }

    var defaultExportFilename: String {
      let identity =
        selectedDevice.map { String(format: "%04X-%04X", $0.vendorID, $0.productID) }
        ?? "controller"
      return "OpenJoystickDriver-packets-\(identity).json"
    }

    func requestRefresh() {
      replaceOperation { model, generation in await model.performRefresh(generation: generation) }
    }

    func refresh() async {
      await replaceOperation { model, generation in
        await model.performRefresh(generation: generation)
      }.value
    }

    private func performRefresh(generation: UInt64) async {
      guard operationIsCurrent(generation) else { return }
      loadState = .loading
      do {
        let status = try await gateway.status()
        guard operationIsCurrent(generation) else { return }
        devices = status.connectedDevices
        guard !devices.isEmpty else {
          selectedDevice = nil
          latestInput = nil
          packets = []
          observedExtraInputs = []
          loadState = .noControllers
          return
        }

        let selectedIdentifier = selectedDevice?.runtimeIdentifier
        selectedDevice = devices.first { $0.runtimeIdentifier == selectedIdentifier } ?? devices[0]
        loadState = .ready
        if let selectedDevice { await refreshSnapshot(for: selectedDevice, generation: generation) }
      } catch {
        guard operationIsCurrent(generation) else { return }
        loadState = .unavailable(RuntimePresentation.userFacingError(error))
      }
    }

    func selectDevice(runtimeIdentifier: String) {
      guard let device = devices.first(where: { $0.runtimeIdentifier == runtimeIdentifier }),
        device.runtimeIdentifier != selectedDevice?.runtimeIdentifier
      else { return }
      selectedDevice = device
      latestInput = nil
      packets = []
      observedExtraInputs = []
      replaceOperation { model, generation in
        await model.refreshSnapshot(for: device, generation: generation)
      }
    }

    func startCapture() {
      guard let device = selectedDevice, !isCapturing else { return }
      packets = []
      observedExtraInputs = []
      captureState = .starting
      replaceOperation { model, generation in
        await model.captureLoop(device: device, generation: generation)
      }
    }

    func stopCapture() {
      let finalState: CaptureState = packets.isEmpty ? .noPackets : .stopped
      captureState = finalState
      replaceOperation { model, generation in
        guard model.operationIsCurrent(generation) else { return }
        model.captureState = finalState
      }
    }

    func clearCapture() {
      packets = []
      observedExtraInputs = []
      if !isCapturing { captureState = .idle }
    }

    func close() {
      captureState = .idle
      replaceOperation { model, generation in
        guard model.operationIsCurrent(generation) else { return }
        model.captureState = .idle
      }
    }

    func encodedPacketLog() throws -> Data {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      return try encoder.encode(packets)
    }

    /// Asks for a destination and writes the captured packets there; a failed write shows an alert.
    func exportPacketCapture() {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string(
        "developer.exportCapture"
      )
      panel.nameFieldStringValue = defaultExportFilename
      panel.canCreateDirectories = true
      panel.begin { [weak self] response in
        guard response == .OK, let url = panel.url, let self else { return }
        do { try self.encodedPacketLog().write(to: url, options: .atomic) } catch {
          NSAlert(error: error).runModal()
        }
      }
    }

    /// Copies the captured packets to the general pasteboard as aligned text rows.
    func copyPacketCapture() {
      let header = OJDLocalized.string(
        "developer.packetColumns"
      )
      let firstTimestamp = packets.first?.timestamp ?? 0
      let rows = [header] + packets.map { Self.packetLine($0, firstTimestamp: firstTimestamp) }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(rows.joined(separator: "\n"), forType: .string)
    }

    private static func packetLine(_ packet: PacketLogEntry, firstTimestamp: TimeInterval) -> String
    {
      let direction = packet.direction.rawValue.uppercased().padding(
        toLength: 9,
        withPad: " ",
        startingAt: 0
      )
      return String(
        format: "+%7.3fs  %@  %5d  %@",
        packet.timestamp - firstTimestamp,
        direction,
        packet.length,
        packet.hex
      )
    }

    private func refreshSnapshot(
      for device: ApplicationServiceDeviceDescription,
      generation: UInt64
    ) async {
      let selector = RuntimeDeviceSelector(device: device)
      do {
        async let input = gateway.controllerState(for: selector)
        async let packetLog = gateway.packetLog(for: selector)
        let (nextInput, nextPackets) = try await (input, packetLog)
        guard operationIsCurrent(generation, device: device) else { return }
        latestInput = nextInput
        packets = nextPackets
        updateObservedExtraInputs(from: latestInput)
        captureState = packets.isEmpty ? .noPackets : .idle
      } catch {
        guard operationIsCurrent(generation, device: device) else { return }
        captureState = .failed(RuntimePresentation.userFacingError(error))
      }
    }

    private func captureLoop(device: ApplicationServiceDeviceDescription, generation: UInt64) async
    {
      let selector = RuntimeDeviceSelector(device: device)
      do {
        var cursor = PacketLogSnapshotCursor(snapshot: try await gateway.packetLog(for: selector))
        guard operationIsCurrent(generation, device: device) else { return }
        captureState = .capturing

        while operationIsCurrent(generation, device: device) {
          async let input = gateway.controllerState(for: selector)
          async let packetLog = gateway.packetLog(for: selector)
          let (nextInput, snapshot) = try await (input, packetLog)
          guard operationIsCurrent(generation, device: device) else { return }
          latestInput = nextInput
          updateObservedExtraInputs(from: nextInput)
          packets.append(contentsOf: cursor.consume(snapshot: snapshot))
          if packets.count > 500 { packets.removeFirst(packets.count - 500) }
          try await sleep(pollIntervalNanoseconds)
        }
      } catch is CancellationError { return } catch {
        guard operationIsCurrent(generation, device: device) else { return }
        captureState = .failed(RuntimePresentation.userFacingError(error))
      }
    }

    @discardableResult
    private func replaceOperation(
      _ operation: @escaping @MainActor (DeveloperToolsViewModel, UInt64) async -> Void
    ) -> Task<Void, Never> {
      operationGeneration &+= 1
      let generation = operationGeneration
      let predecessor = operationTask
      predecessor?.cancel()
      let task = Task { [weak self, predecessor] in
        if let predecessor { await predecessor.value }
        guard let self, self.operationIsCurrent(generation) else { return }
        await operation(self, generation)
        if self.operationGeneration == generation { self.operationTask = nil }
      }
      operationTask = task
      return task
    }

    private func operationIsCurrent(
      _ generation: UInt64,
      device: ApplicationServiceDeviceDescription? = nil
    ) -> Bool {
      guard !Task.isCancelled, operationGeneration == generation else { return false }
      guard let device else { return true }
      return selectedDevice?.runtimeIdentifier == device.runtimeIdentifier
    }

    private func updateObservedExtraInputs(from state: ControllerState?) {
      guard let state else { return }
      // Core face/shoulder/stick/dpad set only. Share, Mute, touchpad, and future paddles
      // must surface here so packet-mapped extras are visible in Developer Tools.
      let observed = state.pressed.subtracting(InputTestButtonPresentation.coreDiagnosticControls)
      let extras = Set(observedExtraInputs).union(observed)
      observedExtraInputs = ControlID.allCases.filter(extras.contains)
    }
  }

#endif
