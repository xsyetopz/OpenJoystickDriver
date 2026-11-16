import Foundation
import OpenJoystickDriverTestSupport
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// An Xbox 360 receiver slot on a real USB pipeline, driven by scripted interrupt reads.
struct ReceiverPresencePipelineTests {
  private typealias Receiver = ProtocolPacketFixtures.XUSBReceiver

  let identifier = LogicalControllerID(vendorID: 0x045E, productID: 0x0719, locationID: 7)
  let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 1,
    vendorID: 0x045E,
    productID: 0x0719,
    locationID: 7
  )
  let inquiry: [UInt8] = [0x08, 0x00, 0x0F, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  let playerOneLED: [UInt8] = [
    0x00, 0x00, 0x08, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]

  @Test
  func presenceDisconnectNeutralizesOutputAndStopsController() async {
    let session = RecoveryUSBSession(
      readResults: [
        .success([UInt8](Receiver.presenceConnected)),
        .success([UInt8](Receiver.padData(buttons: 1 << 12))),
        .success([UInt8](Receiver.presenceDisconnected)),
      ],
      readError: .timeout
    )
    let dispatcher = ReceiverRecordingDispatcher()
    let pipeline = makePipeline(sessions: [session], dispatcher: dispatcher)

    let start = Task { await pipeline.start() }
    await waitUntil("dispatcher.stops == [identifier]") { dispatcher.stops == [identifier] }

    #expect(dispatcher.states == [snapshot(.press(.south)), .neutral])
    #expect(await session.writes == [inquiry, playerOneLED])
    await pipeline.stop()
    await start.value
  }

  @Test
  func sessionLossDropsPresenceUntilNextSessionReportsIt() async {
    let first = RecoveryUSBSession(
      readResults: [
        .success([UInt8](Receiver.presenceConnected)),
        .success([UInt8](Receiver.padData(buttons: 1 << 12))),
      ],
      readError: .disconnected
    )
    let second = RecoveryUSBSession(
      readResults: [
        .success([UInt8](Receiver.presenceConnected)),
        .success([UInt8](Receiver.padData(buttons: 1 << 12))),
      ],
      readError: .timeout
    )
    let dispatcher = ReceiverRecordingDispatcher()
    let pipeline = makePipeline(sessions: [first, second], dispatcher: dispatcher)

    let start = Task { await pipeline.start() }
    await waitUntil("dispatcher.states.count == 3") { dispatcher.states.count == 3 }

    // The held button is released with the lost session and pressed again by the next one.
    #expect(
      dispatcher.states == [snapshot(.press(.south)), .neutral, snapshot(.press(.south))]
    )
    #expect(dispatcher.stops == [identifier])
    #expect(await second.writes == [inquiry, playerOneLED])
    await pipeline.stop()
    await start.value
  }

  @Test
  func connectionStateReportsEmptySlotUntilControllerConnects() async {
    let session = RecoveryUSBSession(
      readResults: [.success([UInt8](Receiver.presenceConnected))],
      readError: .timeout
    )
    let pipeline = makePipeline(sessions: [session], dispatcher: ReceiverRecordingDispatcher())
    let binding = ProtocolBinding(
      protocolID: .xboxXUSB,
      variant: .receiver,
      accessBackend: .rawUSB,
      interfaceNumber: 0,
      rule: .catalogRecord,
      matchedPredicates: [],
      record: nil
    )
    let usbInterface = PhysicalInterfaceSignature(hostTransport: .usb)
    let empty = ControllerConnectionState(
      transport: .proprietaryRadioReceiver,
      backend: .rawUSB,
      isConnected: false,
      power: .unknown
    )
    #expect(await pipeline.connectionState(binding: binding, interface: usbInterface) == empty)

    let start = Task { await pipeline.start() }
    await waitUntil("the pipeline reports a connection") {
      await pipeline.connectionState(binding: binding, interface: usbInterface).isConnected
    }
    await pipeline.stop()
    await start.value
  }

  private func makePipeline(
    sessions: [RecoveryUSBSession],
    dispatcher: ReceiverRecordingDispatcher
  ) -> DevicePipeline {
    DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: XUSBDriver(isWirelessReceiver: true),
      dispatcher: dispatcher,
      // The manager's slot pool assigns the LED; the pipeline lights it when the pad connects.
      startupPlayerIndicator: .player1,
      usbTransportProvider: RecoveryUSBProvider(sessions: sessions),
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 1_000_000,
        accessContentionDelayNanoseconds: 1_000_000
      )
    )
  }
}

/// Records dispatched states (not the presence activations) and controller stops.
private final class ReceiverRecordingDispatcher: OutputDispatcher, ControllerLifecycleListener,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var recordedStates: [ControllerState] = []
  private var recordedStops: [LogicalControllerID] = []

  var suppressOutput = false
  var states: [ControllerState] { lock.withLock { recordedStates } }
  var stops: [LogicalControllerID] { lock.withLock { recordedStops } }

  func dispatch(
    _ event: ControllerEvent,
    from _: LogicalControllerID
  ) { lock.withLock { recordedStates.append(event.state) } }

  func activateOutput(for _: LogicalControllerID) {}

  func controllerDidStop(_ identifier: LogicalControllerID) {
    lock.withLock { recordedStops.append(identifier) }
  }
}
