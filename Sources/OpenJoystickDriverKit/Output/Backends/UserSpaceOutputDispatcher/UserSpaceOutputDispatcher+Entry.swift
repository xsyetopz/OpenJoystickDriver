import Foundation

extension UserSpaceOutputDispatcher {
  /// The virtual gamepad state last built for the input report of `identifier`.
  ///
  /// It is nil when no virtual device exists for `identifier`.
  public func virtualOutputState(for identifier: LogicalControllerID) -> VirtualGamepadState? {
    registryLock.withLock { entries[identifier]?.inputReportState.currentState() }
  }

  /// A virtual device with the sender that feeds it and its input report state.
  final class Entry: Sendable {
    /// The queue that submits reports to the device.
    let sender: UserSpaceReportSender
    /// The state of the device's input report.
    let inputReportState: UserSpaceInputReportState

    /// Creates an entry and attaches `backend` to a sender with a queue of `frameQueueCapacity`
    /// frames.
    init(
      backend: any VirtualDeviceBackend,
      inputReportState: UserSpaceInputReportState,
      frameQueueCapacity: Int = ControllerTuning.defaultFrameQueueCapacity
    ) {
      sender = UserSpaceReportSender(queueCapacity: frameQueueCapacity)
      self.inputReportState = inputReportState
      sender.attach(backend)
    }

    deinit { beginClose() }

    /// Closes the input state before the sender.
    ///
    /// Both closes are idempotent, and the sender returns its one shared close task to every
    /// caller.
    @discardableResult
    func beginClose() -> Task<Void, Never> {
      inputReportState.close()
      return sender.beginClose()
    }

    /// Closes the entry and waits until the device is closed.
    func close() async { await beginClose().value }
  }
}
