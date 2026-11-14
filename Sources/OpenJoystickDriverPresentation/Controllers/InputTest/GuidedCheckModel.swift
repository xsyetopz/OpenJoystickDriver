#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Foundation
  import OpenJoystickDriverKit

  /// What a guided check does outside the window: reads the record, writes the file, shows it in
  /// the file viewer, opens an address and fills the pasteboard.
  struct GuidedCheckEnvironment {
    /// Returns the effective record of the controller's model, or nil.
    var record: (ApplicationServiceDeviceDescription) -> ControllerRecord?
    /// The folder Open Issue saves the document in.
    var saveDirectory: URL
    /// Shows a file in the file viewer.
    var reveal: (URL) -> Void
    /// Opens an address in the browser.
    var open: (URL) -> Void
    /// Replaces the pasteboard text.
    var copy: (String) -> Void

    /// The Mac's record store, Downloads folder, file viewer, browser and general pasteboard.
    static var live: Self {
      Self(
        record: {
          ControllerRecordSet.load(userDirectory: ControllerRecordSet.userDirectory).records[
            ControllerModelID(vendorID: $0.vendorID, productID: $0.productID)
          ]
        },
        saveDirectory: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
        reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        open: { NSWorkspace.shared.open($0) },
        copy: {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString($0, forType: .string)
        }
      )
    }
  }

  /// The state of the Guided Check of Input Test: the run, the finished document and the sheets
  /// that show it.
  @MainActor
  final class GuidedCheckModel: ObservableObject {
    /// The running check, or nil.
    @Published
    private(set) var run: ControllerCheckRun?
    /// The document of the latest finished check, or nil.
    @Published
    private(set) var result: ControllerCheck?
    /// Whether the end sheet shows.
    @Published
    var isEndSheetPresented = false
    /// Whether the validation sheet shows.
    @Published
    var isValidationPresented = false
    /// The message of the latest failed save, or nil.
    @Published
    private(set) var failure: String?

    private let environment: GuidedCheckEnvironment
    private var device: ApplicationServiceDeviceDescription?

    /// Creates the model on `environment`.
    init(environment: GuidedCheckEnvironment = .live) { self.environment = environment }

    /// Starts a check of `device`, one step per control it declares.
    func start(_ device: ApplicationServiceDeviceDescription) {
      self.device = device
      result = nil
      failure = nil
      run = ControllerCheckRun(controls: ControllerCheckControl.steps(for: device.capabilities))
    }

    /// Reads one input state of the controller under check.
    func observe(_ state: ControllerState) {
      run?.observe(state)
      presentIfFinished()
    }

    /// Ends the current step as skipped.
    func skip() {
      run?.skip()
      presentIfFinished()
    }

    /// Drops the running check without a result.
    func cancel() { run = nil }

    /// The text of the validation, or nil unless every control responded.
    var validationText: String? { result.flatMap(ControllerCheckIssue.validationText) }

    /// Saves the document in the Downloads folder, shows it in the file viewer and opens the issue
    /// form of a controller problem, which holds only short fields.
    func openIssue() {
      guard let result, let file = write(result) else { return }
      environment.reveal(file)
      environment.open(ControllerCheckIssue.supportURL(for: result))
    }

    /// Asks where to save the document and writes it there.
    func save() {
      guard let result else { return }
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("ui.inputTest.guidedCheck.title")
      panel.nameFieldStringValue = Self.fileName(of: result)
      panel.begin { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in _ = self?.write(result, to: url) }
      }
    }

    /// Copies the document to the pasteboard.
    func copy() {
      guard let result else { return }
      do { environment.copy(try result.documentText()) } catch {
        failure = RuntimePresentation.userFacingError(error)
      }
    }

    /// Opens the prefilled validation form and closes the validation sheet.
    func confirmValidation() {
      isValidationPresented = false
      guard let result, validationText != nil else { return }
      environment.open(ControllerCheckIssue.validationURL(for: result))
    }

    private func presentIfFinished() {
      guard let run, run.isFinished, let device else { return }
      result = ControllerCheck(
        device: device,
        record: environment.record(device),
        steps: run.results
      )
      self.run = nil
      isEndSheetPresented = true
    }

    private func write(_ check: ControllerCheck, to url: URL? = nil) -> URL? {
      let file = url ?? environment.saveDirectory.appendingPathComponent(Self.fileName(of: check))
      do {
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try Data(check.documentText().utf8).write(to: file, options: .atomic)
        failure = nil
        return file
      } catch {
        failure = RuntimePresentation.userFacingError(error)
        return nil
      }
    }

    private static func fileName(of check: ControllerCheck) -> String {
      let ids = [check.controller.vendorID, check.controller.productID].map {
        String($0, radix: 16)
      }
      return "ojd-controller-check-\(ids.joined(separator: "-")).json"
    }
  }

#endif
