import Foundation

extension UserSpaceOutputDispatcher {
  final class Entry: Sendable {
    let sender: UserSpaceReportSender
    let inputReportState: UserSpaceInputReportState

    convenience init(
      backend: any VirtualDeviceBackend,
      inputReportState: UserSpaceInputReportState
    ) {
      self.init(inputReportState: inputReportState)
      sender.attach(backend)
    }

    /// An entry whose backend is attached later, once the host report handler exists.
    init(inputReportState: UserSpaceInputReportState) {
      sender = UserSpaceReportSender()
      self.inputReportState = inputReportState
    }

    deinit { beginClose() }

    /// Closes the input state before the sender. Both closes are idempotent, and the sender
    /// returns its one shared close task to every caller.
    @discardableResult
    func beginClose() -> Task<Void, Never> {
      inputReportState.close()
      return sender.beginClose()
    }

    func close() async { await beginClose().value }
  }
}
