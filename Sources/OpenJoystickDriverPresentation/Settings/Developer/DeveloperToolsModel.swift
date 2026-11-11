#if canImport(AppKit) && canImport(SwiftUI)

  import Combine
  import AppKit
  import Foundation
  import OpenJoystickDriverKit

  /// The state and actions of the developer tools: the connected controllers, the input of the
  /// selected controller and the raw packet capture.
  @MainActor
  final class DeveloperToolsViewModel: ObservableObject {
    /// Which packets the table shows.
    enum PacketFilter: Hashable {
      /// The packets that carry input activity.
      case activity
      /// Every packet.
      case all
    }

    /// Whether the list of controllers is loaded.
    enum LoadState: Equatable {
      /// Nothing is read.
      case idle
      /// A read is running.
      case loading
      /// The controllers are listed.
      case ready
      /// No controller is connected.
      case noControllers
      /// The read failed; the value is the error text.
      case unavailable(String)
    }

    /// Where the packet capture is.
    enum CaptureState: Equatable {
      /// No capture has started.
      case idle
      /// A capture is starting.
      case starting
      /// Packets are being captured.
      case capturing
      /// The capture stopped with packets.
      case stopped
      /// The capture ended with no packets.
      case noPackets
      /// The capture failed; the value is the error text.
      case failed(String)
    }

    /// Waits for a number of nanoseconds.
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    /// Whether the list of controllers is loaded.
    @Published
    private(set) var loadState: LoadState = .idle
    /// Where the packet capture is.
    @Published
    private(set) var captureState: CaptureState = .idle
    /// The connected controllers.
    @Published
    private(set) var devices: [ApplicationServiceDeviceDescription] = []
    /// The controller that the Controller picker selects.
    @Published
    private(set) var selectedDevice: ApplicationServiceDeviceDescription?

    /// Why the last export of the packet capture failed, or nil.
    @Published
    private(set) var exportError: String?
    /// The latest input of the selected controller.
    @Published
    private(set) var latestInput: ControllerState?
    /// The captured packets; a capture keeps the latest 500.
    @Published
    private(set) var packets: [PacketLogEntry] = []
    /// The controls pressed outside the core face, shoulder, stick and D-pad set, in control order.
    @Published
    private(set) var observedExtraInputs: [Control] = []
    /// Which packets the table shows.
    @Published
    var packetFilter = PacketFilter.activity

    /// The packets the table shows for ``packetFilter``.
    ///
    /// The filter affects only the table; copy and export keep ``packets``.
    var displayedPackets: [PacketLogEntry] {
      switch packetFilter {
      case .activity: packets.filter { $0.classification == .activity }
      case .all: packets
      }
    }

    /// How many packets the filter hides.
    var hiddenIdlePacketCount: Int { packets.count - displayedPackets.count }

    /// The soak test of the Soak Test sheet.
    let soakTest: SoakTestModel

    /// The service connection that the reads use.
    private let gateway: any ApplicationServiceGateway
    /// The wait between polls while capturing.
    private let pollIntervalNanoseconds: UInt64
    /// Waits between polls.
    private let sleep: Sleep
    /// The read or capture that runs, or nil for none.
    private var operationTask: Task<Void, Never>?
    /// Counts the started operations, so that an operation can tell whether a later one replaced
    /// it.
    private var operationGeneration: UInt64 = 0

    /// Whether a read or a capture runs.
    var hasActiveOperation: Bool { operationTask != nil }

    /// Creates the model on a service connection.
    init(
      gateway: any ApplicationServiceGateway,
      soakSource: SoakTestModel.Source? = nil,
      pollIntervalNanoseconds: UInt64 = 50_000_000,
      sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
      self.gateway = gateway
      soakTest = SoakTestModel(source: soakSource ?? .service(gateway: gateway))
      self.pollIntervalNanoseconds = pollIntervalNanoseconds
      self.sleep = sleep
    }

    /// Whether a capture is starting or running.
    var isCapturing: Bool {
      if case .capturing = captureState { return true }
      if case .starting = captureState { return true }
      return false
    }

    /// The file name that Export offers: the USB ID of the selected controller, or `controller`
    /// when none is selected.
    var defaultExportFilename: String {
      let identity =
        selectedDevice.map { unsafe String(format: "%04X-%04X", $0.vendorID, $0.productID) }
        ?? "controller"
      return "OpenJoystickDriver-packets-\(identity).json"
    }

    /// Starts a read and shows it as loading at once, so the view never shows the previous state
    /// for the turn before the read begins.
    func requestRefresh() {
      loadState = .loading
      replaceOperation { model, generation in await model.performRefresh(generation: generation) }
    }

    /// Reads the connected controllers and the input of the selected one, and returns when the read
    /// ends.
    func refresh() async {
      loadState = .loading
      await replaceOperation { model, generation in
        await model.performRefresh(generation: generation)
      }.value
    }

    /// Reads the connected controllers and keeps the selected one while it is connected, then reads
    /// its snapshot.
    ///
    /// A replaced read changes nothing.
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

        let selectedIdentifier = selectedDevice?.sessionToken.rawValue
        selectedDevice =
          devices.first { $0.sessionToken.rawValue == selectedIdentifier } ?? devices[0]
        loadState = .ready
        if let selectedDevice { await refreshSnapshot(for: selectedDevice, generation: generation) }
      } catch {
        guard operationIsCurrent(generation) else { return }
        loadState = .unavailable(RuntimePresentation.userFacingError(error))
      }
    }

    /// Selects the controller with the session token, clears the previous input and packets, and
    /// reads its snapshot.
    func selectDevice(sessionToken: String) {
      guard let device = devices.first(where: { $0.sessionToken.rawValue == sessionToken }),
        device.sessionToken.rawValue != selectedDevice?.sessionToken.rawValue
      else { return }
      selectedDevice = device
      latestInput = nil
      packets = []
      observedExtraInputs = []
      replaceOperation { model, generation in
        await model.refreshSnapshot(for: device, generation: generation)
      }
    }

    /// Starts capturing the packets of the selected controller; does nothing while a capture runs.
    func startCapture() {
      guard let device = selectedDevice, !isCapturing else { return }
      packets = []
      observedExtraInputs = []
      captureState = .starting
      replaceOperation { model, generation in
        await model.captureLoop(device: device, generation: generation)
      }
    }

    /// Stops the capture.
    func stopCapture() {
      let finalState: CaptureState = packets.isEmpty ? .noPackets : .stopped
      captureState = finalState
      replaceOperation { model, generation in
        guard model.operationIsCurrent(generation) else { return }
        model.captureState = finalState
      }
    }

    /// Clears the captured packets and the extra controls; the capture state returns to its start
    /// while no capture runs.
    func clearCapture() {
      packets = []
      observedExtraInputs = []
      if !isCapturing { captureState = .idle }
    }

    /// Stops capture, any running read and a running soak test.
    ///
    /// A read cancelled before it finished leaves `.idle`, which means the diagnostics are not
    /// loaded.
    func close() {
      soakTest.cancel()
      captureState = .idle
      if loadState == .loading { loadState = .idle }
      replaceOperation { model, generation in
        guard model.operationIsCurrent(generation) else { return }
        model.captureState = .idle
      }
    }

    /// Returns the captured packets as sorted, pretty-printed JSON.
    ///
    /// - Throws: the error of `JSONEncoder` when the packets cannot be encoded.
    func encodedPacketLog() throws -> Data {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      return try encoder.encode(packets)
    }

    /// Asks for a destination and writes the captured packets there; a failed write shows in
    /// ``exportError``, beside the Export button.
    func exportPacketCapture() {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string(
        "ui.developer.exportCapture"
      )
      panel.nameFieldStringValue = defaultExportFilename
      panel.canCreateDirectories = true
      panel.begin { [weak self] response in
        guard response == .OK, let url = panel.url, let self else { return }
        writePacketCapture(to: url)
      }
    }

    /// Writes the captured packets to `url` and sets ``exportError`` to the reason a write fails,
    /// or to nil when it succeeds.
    func writePacketCapture(to url: URL) {
      do {
        try encodedPacketLog().write(to: url, options: .atomic)
        exportError = nil
      } catch { exportError = RuntimePresentation.userFacingError(error) }
    }

    /// Copies the captured packets to the general pasteboard as aligned text rows.
    func copyPacketCapture() {
      // The widths match `packetLine`.
      // FSI and PDI (UAX #9) isolate each label, so labels keep column order in any script.
      let header = [
        (OJDLocalized.string("ui.developer.packetColumnTime"), 9),
        (OJDLocalized.string("ui.developer.packetColumnDirection"), 9),
        (OJDLocalized.string("ui.developer.packetColumnBytes"), 5),
        (OJDLocalized.string("ui.developer.packetColumnData"), 0),
      ].map { label, width in
        "\u{2068}\(label)\u{2069}" + String(repeating: " ", count: max(width - label.count, 0))
      }.joined(separator: "  ")
      let firstTimestamp = packets.first?.timestamp ?? 0
      let rows = [header] + packets.map { Self.packetLine($0, firstTimestamp: firstTimestamp) }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(rows.joined(separator: "\n"), forType: .string)
    }

    /// Returns the text row of a packet: its time since `firstTimestamp`, direction, length and
    /// bytes.
    private static func packetLine(_ packet: PacketLogEntry, firstTimestamp: TimeInterval) -> String
    {
      let direction = packet.direction.rawValue.uppercased().padding(
        toLength: 9,
        withPad: " ",
        startingAt: 0
      )
      return unsafe String(
        format: "+%7.3fs  %@  %5d  %@",
        packet.timestamp - firstTimestamp,
        direction,
        packet.length,
        packet.hex
      )
    }

    /// Reads the input and the packet log of `device` once and shows them.
    private func refreshSnapshot(
      for device: ApplicationServiceDeviceDescription,
      generation: UInt64
    ) async {
      let selector = ControllerReference.session(device.sessionToken)
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

    /// Polls the input and the packet log of `device` and appends the packets that arrived since
    /// the last poll, until another operation replaces it.
    private func captureLoop(device: ApplicationServiceDeviceDescription, generation: UInt64) async
    {
      let selector = ControllerReference.session(device.sessionToken)
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

    /// Cancels the running operation, runs `operation` after it ends and returns its task.
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
        guard let self, operationIsCurrent(generation) else { return }
        await operation(self, generation)
        if operationGeneration == generation { operationTask = nil }
      }
      operationTask = task
      return task
    }

    /// Returns whether the operation of `generation` is the latest one and, when `device` is given,
    /// still concerns the selected controller.
    private func operationIsCurrent(
      _ generation: UInt64,
      device: ApplicationServiceDeviceDescription? = nil
    ) -> Bool {
      guard !Task.isCancelled, operationGeneration == generation else { return false }
      guard let device else { return true }
      return selectedDevice?.sessionToken.rawValue == device.sessionToken.rawValue
    }

    /// Adds the controls pressed outside the core face, shoulder, stick and D-pad set to
    /// ``observedExtraInputs``.
    private func updateObservedExtraInputs(from state: ControllerState?) {
      guard let state else { return }
      // Core face/shoulder/stick/dpad set only. Share, Mute, touchpad, and future paddles
      // must surface here so packet-mapped extras are visible in Developer Tools.
      let observed = state.pressed.subtracting(InputTestButtonPresentation.coreDiagnosticControls)
      let extras = Set(observedExtraInputs).union(observed)
      observedExtraInputs = Control.allCases.filter(extras.contains)
    }
  }

#endif
