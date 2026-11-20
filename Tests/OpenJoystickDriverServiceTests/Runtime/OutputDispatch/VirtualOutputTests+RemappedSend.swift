import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// Counts the reads of the controller descriptions, which also answer the session state.
private final class DescriptionReads: @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0
  var count: Int { lock.withLock { reads } }
  func record() { lock.withLock { reads += 1 } }
}

extension VirtualOutputTests {
  @Test
  func remappedStateOfPublishedControllerReadsAsMuchAsAnInputReport() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let reads = DescriptionReads()
    let log = RetargetEventLog()
    let values = [id: description(id)]
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(
        dispatcher: LoggingOutputDispatcher(),
        installationKey: testPortKeyInstallationKey
      ),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { profile in
        let backend = RetargetBackendProbe(profile: profile, log: log)
        log.append(backend)
        return backend
      },
      descriptionsProvider: {
        reads.record()
        return values
      }
    )
    let state = RemappingGamepadState(buttons: [.south])
    try await dispatcher.send(state, for: id)
    let beforeInput = reads.count
    await dispatcher.dispatch(ControllerEvent([.press(.south)]), from: id)
    let inputReads = reads.count - beforeInput
    let beforeStates = reads.count

    for _ in 0..<10 { try await dispatcher.send(state, for: id) }

    #expect(reads.count - beforeStates == 10 * inputReads)
    #expect(log.snapshot().filter { $0.hasSuffix(" state") }.count == 11)
    #expect(log.built().count == 1)
    await dispatcher.close()
  }
}
