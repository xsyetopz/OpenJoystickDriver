import Foundation
import OpenJoystickDriverKit

/// The actions of the Controllers detail that run longer than a click or end in a file: exporting
/// the virtual gamepad mapping, launching a game with it, and the timed captures.
@MainActor
final class ControllerDetailActions: ObservableObject {
  /// A capture that runs for a duration the user picks in a sheet.
  enum TimedKind: Identifiable, Equatable {
    /// A controller record drafted from the packets.
    case draftRecord
    /// The packets as a JSON file.
    case capturePackets

    /// The kind itself.
    var id: Self { self }
  }

  /// Where the timed capture is.
  enum TimedState: Equatable {
    /// No capture runs.
    case idle
    /// A capture runs.
    case capturing
    /// The capture failed; the value is the message for the sheet.
    case failed(String)
  }

  /// A file to ask the user where to save.
  struct SaveRequest: Equatable {
    /// The contents of the file.
    let data: Data
    /// The suggested file name.
    let fileName: String
    /// The folder the panel opens in, when it exists.
    let directory: URL?
    /// Said after the file is written, ahead of the file name.
    let summary: String?
  }

  /// The result of the latest action, shown under the action.
  struct Notice: Equatable {
    /// The action that ended in the notice, so each action shows only its own.
    enum Source: Equatable {
      /// Exporting the mapping of a virtual gamepad.
      case exportMapping
      /// A timed capture.
      case timedCapture
    }

    /// The action that ended in the notice.
    let source: Source
    /// The text of the notice.
    let text: String
    /// Whether the notice reports a failure.
    let isError: Bool
  }

  /// The kind of the timed capture whose sheet is open, or nil.
  @Published
  var timedKind: TimedKind?
  /// Where the timed capture is.
  @Published
  private(set) var timedState: TimedState = .idle
  /// The file waiting for the user to choose where to save it, or nil.
  @Published
  private(set) var pendingSave: SaveRequest?
  /// The result of the latest action, or nil.
  @Published
  private(set) var notice: Notice?
  /// How the latest launch went, or nil.
  @Published
  private(set) var launchOutcome: VirtualGamepadLaunch.Outcome?

  /// The task of the running capture.
  private var timedTask: Task<Void, Never>?
  /// Names the latest capture; an earlier one that ends later changes nothing.
  private var timedGeneration: UInt64 = 0
  /// The program that the latest launch started.
  private var launched: Process?
  /// Names the latest launch; the end of an earlier program does not replace its outcome.
  private var launchGeneration: UInt64 = 0

  // MARK: - Timed captures

  /// Captures `device` for `seconds`, then asks for a place to save the result: the packets as
  /// JSON, or the record drafted from them.
  ///
  /// A failure stays in ``timedState`` for the sheet.
  ///
  /// - Parameters:
  ///   - kind: Whether to capture packets or to draft a record.
  ///   - device: The controller to capture.
  ///   - gateway: The gateway that streams the packets.
  ///   - seconds: How long to capture.
  ///   - descriptor: Reads the report descriptor of the controller, off the main actor.
  func startTimed(
    _ kind: TimedKind,
    device: ApplicationServiceDeviceDescription,
    gateway: any ControllerDiagnosticsGateway,
    seconds: Double,
    descriptor: @escaping @Sendable () -> [UInt8]?
  ) {
    timedTask?.cancel()
    timedGeneration &+= 1
    let generation = timedGeneration
    timedState = .capturing
    timedTask = Task { [weak self] in
      do {
        let packets = try await ControllerPacketCapture.collect(
          from: device,
          gateway: gateway,
          seconds: seconds
        )
        try Task.checkCancellation()
        // The system call that reads the descriptor runs off the main actor.
        let report = await Task.detached { descriptor() }.value
        guard let self, self.timedGeneration == generation else { return }
        self.finishCapture(kind, device: device, packets: packets, descriptor: report)
      } catch is CancellationError {
        guard let self, self.timedGeneration == generation else { return }
        self.timedState = .idle
      } catch let error as ControllerRecordDrafting.NoLayout {
        guard let self, self.timedGeneration == generation else { return }
        self.timedState = .failed(error.message)
      } catch {
        guard let self, self.timedGeneration == generation else { return }
        self.timedState = .failed(RuntimePresentation.userFacingError(error))
      }
    }
  }

  /// Turns the captured packets into the file to save: the packets as JSON, or the drafted record.
  ///
  /// A capture without packets, or a draft without a layout, fails the sheet.
  ///
  /// - Parameters:
  ///   - kind: Whether the packets or a drafted record are saved.
  ///   - device: The captured controller.
  ///   - packets: The captured packets.
  ///   - descriptor: The report descriptor of the controller, or nil.
  private func finishCapture(
    _ kind: TimedKind,
    device: ApplicationServiceDeviceDescription,
    packets: [PacketLogEntry],
    descriptor: [UInt8]?
  ) {
    do {
      switch kind {
      case .capturePackets:
        guard !packets.isEmpty else {
          timedState = .failed(OJDLocalized.string("cli.controller.capture.noPackets"))
          return
        }
        pendingSave = SaveRequest(
          data: try ControllerPacketCapture.exportData(packets),
          fileName: ControllerPacketCapture.fileName(for: device),
          directory: nil,
          summary: nil
        )
      case .draftRecord:
        let draft = try ControllerRecordDrafting.draft(
          for: device,
          packets: packets,
          descriptor: descriptor
        )
        pendingSave = SaveRequest(
          data: draft.document,
          fileName: ControllerRecordDrafting.fileName(for: device),
          directory: Self.recordDirectory,
          summary: OJDLocalized.formatted("cli.record.draft.captured", draft.capturedReports)
        )
      }
      timedState = .idle
      timedKind = nil
    } catch let error as ControllerRecordDrafting.NoLayout {
      timedState = .failed(error.message)
    } catch { timedState = .failed(RuntimePresentation.userFacingError(error)) }
  }

  /// The user record folder, when it exists, for the save panel of a drafted record.
  private static var recordDirectory: URL? {
    let directory = ControllerRecordSet.userDirectory
    return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
  }

  /// Drafts a record from the SDL_GameControllerDB line of `device`, then asks for a place to save
  /// it.
  ///
  /// A failure becomes the notice under the timed actions.
  ///
  /// - Parameter device: The controller.
  func draftFromSDL(device: ApplicationServiceDeviceDescription) {
    do {
      let draft = try ControllerRecordDrafting.sdlDraft(for: device)
      pendingSave = SaveRequest(
        data: draft.document,
        fileName: ControllerRecordDrafting.fileName(for: device),
        directory: Self.recordDirectory,
        summary: nil
      )
    } catch { notice = Notice(source: .timedCapture, text: error.message, isError: true) }
  }

  /// Stops a running capture and closes the sheet.
  func cancelTimed() {
    timedTask?.cancel()
    timedTask = nil
    timedGeneration &+= 1
    timedState = .idle
    timedKind = nil
  }

  /// Writes the pending file to `url`, or drops it when the user cancelled the panel.
  ///
  /// - Parameter url: Where the user chose to save, or nil when the user cancelled.
  func finishSave(to url: URL?) {
    guard let request = pendingSave else { return }
    pendingSave = nil
    guard let url else { return }
    write(request.data, to: url, summary: request.summary, source: .timedCapture)
  }

  // MARK: - Export

  /// Writes the mapping of `profile` in `format` to `url`.
  ///
  /// - Parameters:
  ///   - format: The mapping format.
  ///   - profile: The virtual gamepad profile.
  ///   - url: Where to write the file.
  func exportMapping(
    format: VirtualMappingFormat,
    profile: VirtualHIDProfileID,
    to url: URL
  ) {
    do {
      let text = try VirtualGamepadExport.document(format: format, profile: profile)
      write(Data(text.utf8), to: url, summary: nil, source: .exportMapping)
    } catch {
      notice = Notice(
        source: .exportMapping,
        text: RuntimePresentation.userFacingError(error),
        isError: true
      )
    }
  }

  /// Writes the data to `url` and sets the notice to the saved file or the error.
  ///
  /// - Parameters:
  ///   - data: The contents of the file.
  ///   - url: Where to write the file.
  ///   - summary: Said ahead of the file name, or nil.
  ///   - source: The action that the notice belongs to.
  private func write(
    _ data: Data,
    to url: URL,
    summary: String?,
    source: Notice.Source
  ) {
    do {
      try data.write(to: url, options: .atomic)
      let saved = OJDLocalized.formatted("ui.controllers.fileSaved", url.lastPathComponent)
      notice = Notice(
        source: source,
        text: [summary, saved].compactMap { $0 }.joined(separator: " "),
        isError: false
      )
    } catch { notice = Notice(source: source, text: error.localizedDescription, isError: true) }
  }

  /// Clears the notice.
  func clearNotice() { notice = nil }

  // MARK: - Launch

  /// Starts `program` with the mapping of every virtual gamepad in `devices`.
  ///
  /// The outcome shows that it started, why it could not, and with which status it ended.
  ///
  /// - Parameters:
  ///   - program: The program to start.
  ///   - devices: The connected controllers.
  ///   - gameControllerBackend: Whether the program uses a game controller backend.
  ///   - baseEnvironment: The environment the program starts with, before the mapping is added.
  func launch(
    program: URL,
    devices: [ApplicationServiceDeviceDescription],
    gameControllerBackend: Bool,
    baseEnvironment: [String: String] = VirtualGamepadLaunch.gameEnvironment(
      from: ProcessInfo.processInfo.environment
    )
  ) {
    let name = program.deletingPathExtension().lastPathComponent
    do {
      let prepared = try VirtualGamepadLaunch.prepare(
        program: program,
        devices: devices,
        gameControllerBackend: gameControllerBackend,
        baseEnvironment: baseEnvironment
      )
      let process = ProgramExecutable.process(
        executable: prepared.executable,
        arguments: [],
        environment: prepared.environment,
        standardOutput: FileHandle.nullDevice
      )
      process.standardInput = FileHandle.nullDevice
      launchGeneration &+= 1
      let generation = launchGeneration
      process.terminationHandler = { [weak self] finished in
        let status =
          finished.terminationReason == .uncaughtSignal
          ? 128 + finished.terminationStatus : finished.terminationStatus
        Task { @MainActor in
          guard let self, self.launchGeneration == generation else { return }
          self.launchOutcome = .exited(program: name, status: status)
        }
      }
      try process.run()
      launched = process
      launchOutcome = .started(program: name)
    } catch let failure as VirtualGamepadLaunch.Failure {
      launchOutcome = .failed(failure.message)
    } catch {
      launchOutcome = .failed(
        VirtualGamepadLaunch.Failure.cannotStart(
          program: name,
          reason: error.localizedDescription
        ).message
      )
    }
  }
}
