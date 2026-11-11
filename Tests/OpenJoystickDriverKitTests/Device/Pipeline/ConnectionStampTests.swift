import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// `ControllerState.connection` has one source, the pipeline's
/// `connectionState(binding:interface:)`, stamped when the pipeline dispatches and when the RPC
/// reads the state.
struct ConnectionStampTests {
  static let binding = ProtocolBinding(
    protocolID: .xboxGIP,
    variant: .usb,
    accessBackend: .rawUSB,
    interfaceNumber: nil,
    rule: .catalogRecord,
    matchedPredicates: [],
    record: nil
  )

  @Test
  func aStatusFrameWithoutInputStillChangesTheReadAndDispatchedPower() async throws {
    let dispatcher = StampRecorder()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x045E, productID: 0x02EA),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: StatusFrameDriver(),
      dispatcher: dispatcher,
      binding: Self.binding,
      interface: PhysicalInterfaceSignature(hostTransport: .usb)
    )
    await pipeline.start()
    #expect(await pipeline.inputState().connection?.power == .unknown)

    // A status frame parses to nil: nothing is dispatched, yet the power it decoded is visible.
    await pipeline.feedHIDData(Data([StatusFrameDriver.status]))
    #expect(dispatcher.states.isEmpty)
    let read = try #require(await pipeline.inputState().connection)
    #expect(read.power == StatusFrameDriver.charging)
    #expect(read.transport == .usb && read.backend == .rawUSB && read.isConnected)

    // The next input is dispatched with the same stamped state; it never changes skip-if-unchanged.
    await pipeline.feedHIDData(Data([StatusFrameDriver.press]))
    #expect(dispatcher.states.map(\.pressed) == [[.south]])
    #expect(dispatcher.states.last?.connection == read)
    await pipeline.feedHIDData(Data([StatusFrameDriver.status]))
    await pipeline.feedHIDData(Data([StatusFrameDriver.press]))
    #expect(dispatcher.states.count == 1)
    await pipeline.stop()
  }

  @Test
  func aRouteInstalledWhileAControlIsHeldReceivesItOnTheNextReport() async {
    let dispatcher = NativeEventRecorder()
    dispatcher.demandsInput = false
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x045E, productID: 0x02EA),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: StatusFrameDriver(),
      dispatcher: dispatcher,
      macOSOwnedOutput: MacOSOwnedOutput.none
    )
    await pipeline.start()
    await pipeline.feedHIDData(Data([StatusFrameDriver.press]))
    #expect(dispatcher.states.isEmpty)

    // Demand arrives while South stays held: the unchanged report still delivers it.
    dispatcher.demandsInput = true
    await pipeline.feedHIDData(Data([StatusFrameDriver.press]))
    #expect(dispatcher.states.map(\.pressed) == [[.south]])
    await pipeline.feedHIDData(Data([StatusFrameDriver.press]))
    #expect(dispatcher.states.count == 1)

    // Demand lost and regained while held: the next report delivers the held state again.
    dispatcher.demandsInput = false
    await pipeline.feedHIDData(Data([StatusFrameDriver.press]))
    dispatcher.demandsInput = true
    await pipeline.feedHIDData(Data([StatusFrameDriver.press]))
    #expect(dispatcher.states.map(\.pressed) == [[.south], [.south]])
    await pipeline.stop()
  }
}

private final class StatusFrameDriver: PhysicalProtocolDriver {
  static let status: UInt8 = 0x03
  static let press: UInt8 = 0x20
  static let charging = ControllerConnectionState.Power(
    charging: .charging,
    battery: BatteryLevel(percentage: 40...40),
    wiredPower: true
  )

  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  private(set) var power: ControllerConnectionState.Power?

  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  func parse(report: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    switch report.first {
    case Self.status:
      power = Self.charging
      return nil
    case Self.press: return ControllerEvent([.press(.south)], at: receivedAt.nanoseconds)
    default: return nil
    }
  }
}

private final class StampRecorder: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private let lock = NSLock()
  private var recorded: [ControllerState] = []

  var states: [ControllerState] { lock.withLock { recorded } }

  func dispatch(
    _ event: ControllerEvent,
    from _: LogicalControllerID
  ) { lock.withLock { recorded.append(event.state) } }

  func activateOutput(for _: LogicalControllerID) {}
}
