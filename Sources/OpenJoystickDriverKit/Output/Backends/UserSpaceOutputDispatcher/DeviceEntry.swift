import Foundation

extension UserSpaceOutputDispatcher {
  final class Entry: @unchecked Sendable {
    /// Matches the published IOHID ReportInterval.
    static let inputReportKeepaliveNanoseconds: UInt64 = 8_000_000
    let sender: UserSpaceReportSender
    let inputReportState: UserSpaceInputReportState
    private let lock = NSLock()
    private var keepaliveTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    init(
      backend: any VirtualDeviceBackend,
      inputReportState: UserSpaceInputReportState,
      sender: UserSpaceReportSender = UserSpaceReportSender()
    ) {
      self.sender = sender
      self.inputReportState = inputReportState
      sender.attach(backend)
    }

    deinit { beginClose() }

    func startInputReportKeepalive(
      isActive: @escaping @Sendable () -> Bool,
      sleep: @escaping @Sendable (UInt64) async throws -> Void = {
        try await Task.sleep(nanoseconds: $0)
      }
    ) {
      lock.withLock {
        guard closeTask == nil, keepaliveTask == nil else { return }
        keepaliveTask = Task { [inputReportState, sender] in
          while !Task.isCancelled {
            do { try await sleep(Self.inputReportKeepaliveNanoseconds) } catch { return }
            guard !Task.isCancelled else { return }
            // Suppression pauses publication, not ownership of the keepalive task.
            guard isActive() else { continue }
            _ = await sender.submit(whileActive: isActive) {
              isActive() ? [inputReportState.currentReport()] : []
            }.result
          }
        }
      }
    }

    @discardableResult
    func beginClose() -> Task<Void, Never> {
      lock.withLock {
        if let closeTask { return closeTask }
        inputReportState.hostSession.close()
        let keepalive = keepaliveTask
        keepaliveTask = nil
        keepalive?.cancel()
        let drain = sender.beginClose()
        let task = Task {
          if let keepalive { await keepalive.value }
          await drain.value
        }
        closeTask = task
        return task
      }
    }

    func close() async { await beginClose().value }
  }
}
