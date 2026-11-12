import Foundation

extension DeviceManager {
  /// How often the idle disconnect looks at the connected controllers.
  public static let idleDisconnectCheckNanoseconds: UInt64 = 30_000_000_000

  /// Checks every `interval` nanoseconds for Bluetooth controllers with no changed input for the
  /// minutes `minutes` returns, and disconnects them as the menu's Disconnect does.
  ///
  /// `minutes` returns nil while the setting is off. Replaces an earlier monitor and survives
  /// ``stop()``, so a restart after wake keeps it.
  @preconcurrency
  public func startIdleDisconnectMonitor(
    interval: UInt64 = idleDisconnectCheckNanoseconds,
    minutes: @escaping @Sendable () -> Int?
  ) {
    idleDisconnectTask?.cancel()
    idleDisconnectTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: interval)
        guard !Task.isCancelled, let self else { return }
        guard let threshold = minutes() else { continue }
        await disconnectIdleWirelessControllers(afterMinutes: threshold)
      }
    }
  }

  /// Disconnects each Bluetooth controller whose input state has not changed for `minutes`.
  ///
  /// A cable or receiver connection is never disconnected. A controller whose disconnect fails
  /// gets a full period before the next attempt.
  ///
  /// - Returns: The controllers that disconnected.
  @discardableResult
  package func disconnectIdleWirelessControllers(
    afterMinutes minutes: Int
  ) async
    -> [LogicalControllerID]
  {
    var disconnected: [LogicalControllerID] = []
    for controller in await connectedControllers() {
      guard let pipeline = pipelines[controller.logicalControllerID],
        await pipeline.controllerSessionState() == .active,
        await pipeline.isIdleDisconnectDue(afterMinutes: minutes)
      else { continue }
      let result = await disconnectWirelessController(.session(controller.sessionToken))
      if result.failure == nil {
        disconnected.append(controller.logicalControllerID)
      } else {
        await pipeline.restartIdleWindow()
      }
    }
    return disconnected
  }
}
