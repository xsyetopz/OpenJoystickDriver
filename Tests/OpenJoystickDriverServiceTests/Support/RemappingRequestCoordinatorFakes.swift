import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct CoordinatorHarness {
  let routerHarness: RemappingRouterHarness
  let coordinator: RemappingRequestCoordinator
}

enum RollbackMutation: Sendable {
  case deactivate
  case delete
}

struct TransactionRollbackHarness {
  let directory: URL
  let library: RemappingProfileLibrary
  let router: RemappingOutputRouter
  let coordinator: RemappingRequestCoordinator
  let sink: TransactionFaultSink

  func removeFiles() {
    try? FileManager.default.removeItem(at: directory)
  }
}

final class TransactionFaultSink: RemappingSystemInputSink, @unchecked Sendable {
  private let lock = NSLock()
  private let recorder: RemappingRouterRecorder
  private var pendingFailures = 0

  init(recorder: RemappingRouterRecorder) { self.recorder = recorder }

  func failNextAction() { lock.withLock { pendingFailures += 1 } }

  func send(_ action: RemappingSystemInputAction) throws {
    let shouldFail = lock.withLock { () -> Bool in
      guard pendingFailures > 0 else { return false }
      pendingFailures -= 1
      return true
    }
    guard !shouldFail else { throw RemappingEventEngineError.sinkUnavailable }
    recorder.append(.system(action))
  }
}

final class RPCPostEventProbe: CoreGraphicsPostEventAccessProbing, @unchecked Sendable {
  private let lock = NSLock()
  private let results: [Bool]
  private let requestResult: Bool
  private var preflightIndex = 0
  private var requests = 0

  var preflightCount: Int { lock.withLock { preflightIndex } }
  var requestCount: Int { lock.withLock { requests } }

  init(preflight: [Bool], requestResult: Bool) {
    results = preflight
    self.requestResult = requestResult
  }

  func preflight() -> Bool {
    lock.withLock {
      defer { preflightIndex += 1 }
      return results[min(preflightIndex, results.count - 1)]
    }
  }

  func request() -> Bool {
    lock.withLock { requests += 1 }
    return requestResult
  }
}
