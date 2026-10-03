import Foundation
import OpenJoystickDriverKit

/// The shared `controllers` stream: one poll task for every subscriber.
struct EndpointStream {
  private struct Controller {
    let connected: ControllerWatchEvent
    var input: ControllerWatchEvent?
  }

  /// Bumped on each start, so a cancelled task that is still finishing a poll delivers nothing.
  var generation = 0
  var task: Task<Void, Never>?
  /// The connected controllers in connection order with their last input, for late subscribers.
  private var controllers: [Controller] = []

  /// The events that bring a new subscriber up to date.
  var snapshot: [ControllerWatchEvent] {
    controllers.flatMap { [$0.connected] + ($0.input.map { [$0] } ?? []) }
  }

  /// Cancels the task and forgets the controllers; the generation stays, so the old task's last
  /// poll is dropped.
  mutating func stop() {
    task?.cancel()
    task = nil
    controllers = []
  }

  mutating func record(_ event: ControllerWatchEvent) {
    switch event.type {
    case .connected: controllers.append(Controller(connected: event))
    case .input:
      guard let index = controllers.firstIndex(where: { $0.connected.id == event.id }) else {
        return
      }
      controllers[index].input = event
    case .disconnected: controllers.removeAll { $0.connected.id == event.id }
    }
  }
}

extension EndpointServer {
  /// Sends `connection` the connected controllers, then the stream; starts the poll task for the
  /// first subscriber. Call with `lock` held.
  func subscribe(_ connection: EndpointConnection, output: Bool) {
    connection.subscribe(output: output, snapshot: stream.snapshot)
    guard stream.task == nil else { return }
    stream.generation += 1
    let generation = stream.generation
    stream.task = Task { [weak self] in await self?.runStream(generation: generation) }
  }

  /// Stops the poll task once no connection is subscribed. Call with `lock` held.
  func stopStreamIfIdle() {
    guard stream.task != nil, !connections.values.contains(where: \.isSubscribed) else { return }
    stream.stop()
  }

  private func runStream(generation: Int) async {
    var poller = ControllerWatchPoller(source: source)
    var lastError: String?
    while !Task.isCancelled {
      let includeOutput = lock.withLock { connections.values.contains(where: \.wantsOutputValues) }
      do {
        let updates = try await poller.poll(
          now: DispatchTime.now().uptimeNanoseconds,
          includeOutput: includeOutput
        )
        lastError = nil
        lock.withLock {
          guard stream.generation == generation else { return }
          for update in updates {
            stream.record(update.event)
            for connection in connections.values { connection.deliver(update.event) }
          }
        }
      } catch {
        if lastError != error.localizedDescription {
          lastError = error.localizedDescription
          print("[EndpointServer] Reading controllers failed: \(error.localizedDescription)")
        }
      }
      try? await Task.sleep(nanoseconds: ControllerWatchPoller.pollInterval)
    }
  }
}
