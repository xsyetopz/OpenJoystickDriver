#if canImport(AppKit) && canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit

  @MainActor final class DeveloperToolsViewModel: ObservableObject {
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

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var devices: [ApplicationServiceDeviceDescription] = []
    @Published private(set) var selectedDevice: ApplicationServiceDeviceDescription?
    @Published private(set) var latestInput: DeviceInputState?
    @Published private(set) var packets: [PacketLogEntry] = []
    @Published private(set) var observedExtraInputs: [String] = []

    var diagnosticRecipeAvailable: Bool {
      guard let device = selectedDevice else { return false }
      return ParserRegistry().runtimeProfile(
        for: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
      ).gipStartupPackets.contains(where: \.isDiagnosticRecipe)
    }

    private let gateway: any ApplicationServiceGateway
    private let pollIntervalNanoseconds: UInt64
    private let sleep: Sleep
    private var captureTask: Task<Void, Never>?
    private var captureGeneration: UInt64 = 0
    private var snapshotTask: Task<Void, Never>?
    private var snapshotGeneration: UInt64 = 0

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
      let generation = beginSnapshotRequest()
      snapshotTask = Task { [weak self] in await self?.performRefresh(generation: generation) }
    }

    func refresh() async {
      let generation = beginSnapshotRequest()
      await performRefresh(generation: generation)
    }

    private func performRefresh(generation: UInt64) async {
      guard snapshotRequestIsCurrent(generation) else { return }
      stopCapture(finalState: .idle)
      loadState = .loading
      do {
        let status = try await gateway.status()
        guard snapshotRequestIsCurrent(generation) else { return }
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
        guard snapshotRequestIsCurrent(generation) else { return }
        stopCapture(finalState: .idle)
        loadState = .unavailable(RuntimePresentation.userFacingError(error))
      }
    }

    func selectDevice(runtimeIdentifier: String) {
      guard let device = devices.first(where: { $0.runtimeIdentifier == runtimeIdentifier }),
        device.runtimeIdentifier != selectedDevice?.runtimeIdentifier
      else { return }
      let generation = beginSnapshotRequest()
      stopCapture(finalState: .idle)
      selectedDevice = device
      latestInput = nil
      packets = []
      observedExtraInputs = []
      snapshotTask = Task { [weak self] in
        await self?.refreshSnapshot(for: device, generation: generation)
      }
    }

    func startCapture() {
      guard let device = selectedDevice, !isCapturing else { return }
      beginSnapshotRequest()
      stopCapture(finalState: .starting)
      packets = []
      observedExtraInputs = []
      captureGeneration &+= 1
      let generation = captureGeneration
      let selector = RuntimeDeviceSelector(device: device)
      captureTask = Task { [weak self] in
        await self?.captureLoop(selector: selector, generation: generation)
      }
    }

    func stopCapture() {
      let state: CaptureState = packets.isEmpty ? .noPackets : .stopped
      stopCapture(finalState: state)
    }

    func clearCapture() {
      packets = []
      observedExtraInputs = []
      if !isCapturing { captureState = .idle }
    }

    func close() {
      beginSnapshotRequest()
      stopCapture(finalState: .idle)
    }

    func encodedPacketLog() throws -> Data {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      return try encoder.encode(packets)
    }

    private func refreshSnapshot(
      for device: ApplicationServiceDeviceDescription,
      generation: UInt64
    ) async {
      let selector = RuntimeDeviceSelector(device: device)
      do {
        async let input = gateway.deviceInputState(for: selector)
        async let packetLog = gateway.packetLog(for: selector)
        let (nextInput, nextPackets) = try await (input, packetLog)
        guard snapshotRequestIsCurrent(generation, device: device) else { return }
        latestInput = nextInput
        packets = nextPackets
        updateObservedExtraInputs(from: latestInput)
        captureState = packets.isEmpty ? .noPackets : .idle
      } catch {
        guard snapshotRequestIsCurrent(generation, device: device) else { return }
        captureState = .failed(RuntimePresentation.userFacingError(error))
      }
    }

    private func captureLoop(selector: RuntimeDeviceSelector, generation: UInt64) async {
      do {
        var cursor = PacketLogSnapshotCursor(snapshot: try await gateway.packetLog(for: selector))
        guard captureGeneration == generation else { return }
        captureState = .capturing

        while !Task.isCancelled, captureGeneration == generation {
          async let input = gateway.deviceInputState(for: selector)
          async let packetLog = gateway.packetLog(for: selector)
          let (nextInput, snapshot) = try await (input, packetLog)
          guard captureGeneration == generation else { return }
          latestInput = nextInput
          updateObservedExtraInputs(from: nextInput)
          packets.append(contentsOf: cursor.consume(snapshot: snapshot))
          if packets.count > 500 { packets.removeFirst(packets.count - 500) }
          try await sleep(pollIntervalNanoseconds)
        }
      } catch is CancellationError { return } catch {
        guard captureGeneration == generation else { return }
        captureTask = nil
        captureState = .failed(RuntimePresentation.userFacingError(error))
      }
    }

    private func stopCapture(finalState: CaptureState) {
      captureGeneration &+= 1
      captureTask?.cancel()
      captureTask = nil
      captureState = finalState
    }

    @discardableResult private func beginSnapshotRequest() -> UInt64 {
      snapshotGeneration &+= 1
      snapshotTask?.cancel()
      snapshotTask = nil
      return snapshotGeneration
    }

    private func snapshotRequestIsCurrent(
      _ generation: UInt64,
      device: ApplicationServiceDeviceDescription? = nil
    ) -> Bool {
      guard !Task.isCancelled, snapshotGeneration == generation else { return false }
      guard let device else { return true }
      return selectedDevice?.runtimeIdentifier == device.runtimeIdentifier
    }

    private func updateObservedExtraInputs(from state: DeviceInputState?) {
      guard let state else { return }
      let standardNames = Set(InputTestButtonPresentation.standardButtons.map(\.rawValue))
      let observed = state.pressedButtons.filter { !standardNames.contains($0) }
      observedExtraInputs = Array(Set(observedExtraInputs).union(observed)).sorted()
    }
  }

#endif
