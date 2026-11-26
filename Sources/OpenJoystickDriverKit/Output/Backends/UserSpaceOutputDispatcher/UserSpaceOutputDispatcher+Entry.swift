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
    /// Resends the current input report while the state holds still, for a format that streams;
    /// nil for a format that sends only changes.
    private let streamTask: Task<Void, Never>?

    /// Creates an entry and attaches `backend` to a sender with a queue of `frameQueueCapacity`
    /// frames; `deadlineTimer` lets a test replace the native send deadline timer.
    init(
      backend: any VirtualDeviceBackend,
      inputReportState: UserSpaceInputReportState,
      frameQueueCapacity: Int = ControllerTuning.defaultFrameQueueCapacity,
      deadlineTimer: DeadlineTimer = .dispatch
    ) {
      sender = UserSpaceReportSender(
        queueCapacity: frameQueueCapacity,
        deadlineTimer: deadlineTimer
      )
      self.inputReportState = inputReportState
      sender.attach(backend)
      streamTask = Self.stream(sender: sender, inputReportState: inputReportState)
    }

    /// Starts the task that resends the current report of a streaming format.
    ///
    /// A genuine DualShock 4 sends a report every 4 ms, and a raw HID reader, such as a Windows
    /// game under Wine, may wait for that stream. The task wakes once per interval and submits a
    /// frame only when no report went out within it and no other submission waits, so a moving
    /// state adds no second report and a repeat never evicts a state change.
    private static func stream(
      sender: UserSpaceReportSender,
      inputReportState: UserSpaceInputReportState
    ) -> Task<Void, Never>? {
      guard let interval = inputReportState.reportIntervalNanoseconds, interval > 0 else {
        return nil
      }
      return Task.detached(priority: .userInitiated) { [weak sender, weak inputReportState] in
        while !Task.isCancelled {
          do { try await Task.sleep(nanoseconds: interval) } catch { return }
          guard let sender, let inputReportState, !inputReportState.isClosed else { return }
          _ = sender.submit(isFrame: true, onlyWhenIdle: true) {
            inputReportState.dueRepeat().map { [$0] } ?? []
          }
        }
      }
    }

    deinit { beginClose() }

    /// Closes the input state before the sender.
    ///
    /// Both closes are safe to repeat, and the sender returns its one shared close task to every
    /// caller.
    @discardableResult
    func beginClose() -> Task<Void, Never> {
      streamTask?.cancel()
      inputReportState.close()
      return sender.beginClose()
    }

    /// Closes the entry and waits until the device is closed.
    func close() async { await beginClose().value }
  }
}
