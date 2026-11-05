import Foundation
import OpenJoystickDriverTestSupport
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// One raw-USB pipeline per Xbox 360 receiver slot. The receiver's interface layout is the
/// synthetic 8-interface descriptor of ``ReceiverSlotProvider``; see its comment.
@Suite(.timeLimit(.minutes(2)))
struct ReceiverSlotDiscoveryTests {
  private typealias Receiver = ProtocolPacketFixtures.XUSBReceiver

  private let inquiry: [UInt8] = [0x08, 0x00, 0x0F, 0xC0] + [UInt8](repeating: 0, count: 8)
  private let slotIdentifiers = ReceiverSlotProvider.slotInterfaces.map(
    ReceiverSlotProvider.identifier
  )

  @Test
  func eachSlotInterfaceRunsItsOwnPipelineInSlotOrder() async {
    // Synthetic interface layout (ReceiverSlotProvider); receiver slot numbers are uncaptured.
    let sessions = slotSessions { _ in [.success([UInt8](Receiver.presenceConnected))] }
    let provider = ReceiverSlotProvider(sessions: sessions)
    let manager = makeManager(provider)

    #expect(
      await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
        == .claimed(slotIdentifiers)
    )
    for (ordinal, interface) in ReceiverSlotProvider.slotInterfaces.enumerated() {
      let session = sessions[interface]
      await waitUntil("session?.writeCount == 2") { await session?.writeCount == 2 }
      // Slot n asks for presence, then lights player n+1 (0x46 + n) once a pad is present.
      #expect(await session?.writes == [inquiry, ledPacket(0x46 + UInt8(ordinal))])
    }
    // Only slot interfaces open, and the configured receiver is never reconfigured.
    let opened = await provider.openedOptions
    #expect(opened.map(\.interfaceNumber).sorted() == ReceiverSlotProvider.slotInterfaces)
    #expect(opened.allSatisfy { $0.configurationValue == nil })
    #expect(Set(await manager.pipelines.keys) == Set(slotIdentifiers))
    await manager.stop()
  }

  @Test
  func unconfiguredReceiverIsConfiguredOnlyThroughItsFirstSlot() async {
    // Synthetic interface layout (ReceiverSlotProvider); receiver slot numbers are uncaptured.
    let provider = ReceiverSlotProvider(sessions: slotSessions { _ in [] }, isConfigured: false)
    let manager = makeManager(provider)

    #expect(
      await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
        == .claimed(slotIdentifiers)
    )
    await waitUntil("provider.openedOptions.count == 4") { await provider.openedOptions.count == 4 }
    // SET_CONFIGURATION terminates every open interface, so later slots must not send it.
    let configured = await provider.openedOptions.filter { $0.configurationValue == 1 }
    #expect(configured.map(\.interfaceNumber) == [0])
    #expect(await provider.configuringInterfaces == [0])
    #expect(await provider.terminatedInterfaces.isEmpty)
    await manager.stop()
  }

  @Test
  func firstSlotReopenOnAConfiguredReceiverKeepsTheOtherSlots() async {
    // Synthetic interface layout (ReceiverSlotProvider); receiver slot numbers are uncaptured.
    // Slot 0 of a cold receiver requests configuration 1 on every open; its first session is
    // lost after the presence inquiry, and the reopen finds the device already configured.
    var sessions = slotSessions { _ in [] }
    sessions[0] = RecoveryUSBSession(readError: .disconnected)
    let reopened = RecoveryUSBSession(readError: .timeout)
    let provider = ReceiverSlotProvider(
      sessions: sessions,
      reopened: [0: reopened],
      isConfigured: false
    )
    let manager = makeManager(provider)

    #expect(
      await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
        == .claimed(slotIdentifiers)
    )
    await waitUntil("reopened.writeCount > 0") { await reopened.writeCount > 0 }

    let slotZeroOpens = await provider.openedOptions.filter { $0.interfaceNumber == 0 }
    #expect(slotZeroOpens.map(\.configurationValue) == [1, 1])
    #expect(await provider.configuringInterfaces == [0])
    #expect(await provider.terminatedInterfaces.isEmpty)
    await manager.stop()
  }

  @Test(arguments: [
    (UInt8?.none, UInt8?.none, false), (UInt8?.none, UInt8?.some(1), false),
    (UInt8?.some(1), UInt8?.none, true), (UInt8?.some(1), UInt8?.some(0), true),
    (UInt8?.some(1), UInt8?.some(1), false), (UInt8?.some(1), UInt8?.some(2), true),
  ])
  func openSendsOnlyAConfigurationTheDeviceDoesNotRun(
    requested: UInt8?,
    current: UInt8?,
    expected: Bool
  ) {
    let options = USBTransportOpenOptions(configurationValue: requested, interfaceNumber: 0)
    #expect(options.setsConfiguration(current: current) == expected)
  }

  @Test
  func presenceOfOneSlotCreatesAndDestroysOnlyThatController() async {
    // Synthetic interface layout (ReceiverSlotProvider); receiver slot numbers are uncaptured.
    let sessions = slotSessions { interface in
      guard interface == 2 else { return [] }
      return [
        .success([UInt8](Receiver.presenceConnected)),
        .success([UInt8](Receiver.padData(buttons: 1 << 12))),
        .success([UInt8](Receiver.presenceDisconnected)),
      ]
    }
    let provider = ReceiverSlotProvider(sessions: sessions)
    let dispatcher = ReceiverSlotDispatcher()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
    let slot = ReceiverSlotProvider.identifier(interface: 2)

    #expect(
      await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
        == .claimed(slotIdentifiers)
    )
    await waitUntil("dispatcher.stops == [slot]") { dispatcher.stops == [slot] }

    #expect(Array(dispatcher.dispatches.keys) == [slot])
    #expect(dispatcher.dispatches[slot]?.map(\.pressed) == [[.south], []])
    #expect(
      dispatcher.dispatches[slot]?.allSatisfy {
        $0.connection?.transport == .proprietaryRadioReceiver
      } == true
    )
    // The other slots stay idle pipelines with no controller.
    #expect(await manager.pipelines.count == 4)
    await manager.stop()
  }

  @Test
  func detachStopsEverySlotInOnePass() async {
    // Synthetic interface layout (ReceiverSlotProvider); receiver slot numbers are uncaptured.
    let sessions = slotSessions { _ in [] }
    let provider = ReceiverSlotProvider(sessions: sessions)
    let manager = makeManager(provider)
    let detection = Task { await manager.runUSBDetection() }

    await waitUntil("manager.pipelines.count == 4") { await manager.pipelines.count == 4 }
    await provider.setDevices([])
    await waitUntil("manager.pipelines.isEmpty") { await manager.pipelines.isEmpty }

    #expect(await manager.deviceInfos.isEmpty)
    for session in sessions.values {
      await waitUntil("a session closes") { await session.closeCount == 1 }
    }
    detection.cancel()
    await detection.value
    await manager.stop()
  }

  @Test
  func slotFailingAfterAnEarlierSlotStartedRetriesTheWholeService() async {
    // Synthetic interface layout (ReceiverSlotProvider); receiver slot numbers are uncaptured.
    let provider = ReceiverSlotProvider(sessions: slotSessions { _ in [] })
    let manager = makeManager(provider)
    let observer = ReceiverSlotAdmissionCanceller.observe(from: manager)
    defer { NotificationCenter.default.removeObserver(observer) }

    let counter = ReceiverSlotAdmissionCanceller.Counter()
    let admission = Task {
      await ReceiverSlotAdmissionCanceller.$counter.withValue(counter) {
        await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
      }
    }

    #expect(await admission.value == .retry)
    // The second slot's pipeline existed when the admission failed.
    #expect(counter.count >= 2)
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    // The service stays unacknowledged, and the next attempt admits every slot.
    #expect(
      await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
        == .claimed(slotIdentifiers)
    )
    await manager.stop()
  }

  @Test
  func eachSlotIsSelectedByItsOwnPortKey() async throws {
    // Synthetic interface layout (ReceiverSlotProvider); receiver slot numbers are uncaptured.
    let provider = ReceiverSlotProvider(
      sessions: slotSessions { _ in [.success([UInt8](Receiver.presenceConnected))] }
    )
    let manager = makeManager(provider)
    #expect(
      await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
        == .claimed(slotIdentifiers)
    )

    await waitUntil("all four controllers report presence") {
      await manager.connectedDeviceDescriptions().count == 4
    }
    let descriptions = await manager.connectedDeviceDescriptions()
    #expect(Set(descriptions.map(\.sessionToken)).count == 4)
    #expect(Set(descriptions.map(\.inputEndpoint)) == [0x81, 0x83, 0x85, 0x87])
    // Four slots of one model: a model reference selects none of them.
    let untokened = await manager.suspendController(
      .model(ControllerModelID(vendorID: 0x045E, productID: 0x0719))
    )
    #expect(untokened.failure == .notFound)
    let slot = ReceiverSlotProvider.identifier(interface: 4)
    let suspended = await manager.suspendController(.port(try #require(slot.testPortKey)))
    #expect(suspended.state == .suspended)
    for identifier in slotIdentifiers {
      let pipeline = try #require(await manager.pipelines[identifier])
      #expect(
        await pipeline.controllerSessionState() == (identifier == slot ? .suspended : .active)
      )
    }
    await manager.stop()
  }

  @Test
  func emptySlotsAreNotListedOrEligibleForPublication() async {
    let sessions = slotSessions { _ in [] }
    let provider = ReceiverSlotProvider(sessions: sessions)
    let dispatcher = ReceiverSlotDispatcher()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
    #expect(
      await manager.handleUSBDeviceAdded(
        ReceiverSlotProvider.device,
        provider: provider
      ) == .claimed(slotIdentifiers)
    )
    #expect(await manager.pipelines.count == 4)
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await manager.connectedLogicalControllerIDs().isEmpty)
    #expect(await manager.activeLogicalControllerIDs().isEmpty)
    #expect(await manager.connectedControllers().isEmpty)
    #expect(dispatcher.activations.isEmpty)
    for identifier in slotIdentifiers {
      #expect(await manager.controllerSessionState(for: identifier) == nil)
    }
    await manager.stop()
  }

  @Test
  func onlyTheSlotReceivingInputIsListedAndSelectableByModel() async throws {
    let sessions = slotSessions { interface in
      interface == 0 ? [.success([UInt8](Receiver.padData(buttons: 1 << 12)))] : []
    }
    let provider = ReceiverSlotProvider(sessions: sessions)
    let dispatcher = ReceiverSlotDispatcher()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
    #expect(
      await manager.handleUSBDeviceAdded(ReceiverSlotProvider.device, provider: provider)
        == .claimed(slotIdentifiers)
    )
    await waitUntil("one controller reports presence") {
      await manager.connectedDeviceDescriptions().count == 1
    }
    let slot = ReceiverSlotProvider.identifier(interface: 0)
    await waitUntil("only the paired controller activates output") {
      dispatcher.activations == [slot]
    }
    #expect(await manager.connectedLogicalControllerIDs() == [slot])
    #expect(await manager.activeLogicalControllerIDs() == [slot])
    #expect(await manager.controllerSessionState(for: slot) == .active)
    let controllers = await manager.connectedControllers()
    #expect(controllers.map(\.logicalControllerID) == [slot])
    let selected = try ControllerReference.model(slot.model).resolve(in: controllers)
    #expect(selected.logicalControllerID == slot)
    for empty in slotIdentifiers where empty != slot {
      #expect(await manager.deviceDescription(for: empty) == nil)
    }
    let selectedSession = try #require(sessions[0])
    await selectedSession.enqueueReads([.success([UInt8](Receiver.presenceDisconnected))])
    await waitUntil("the disconnected controller is removed") {
      await manager.connectedDeviceDescriptions().isEmpty
    }
    #expect(await manager.pipelines.count == 4)
    #expect(await manager.activeLogicalControllerIDs().isEmpty)
    #expect(await manager.controllerSessionState(for: slot) == nil)
    #expect(dispatcher.stops == [slot])
    await selectedSession.enqueueReads([.success([UInt8](Receiver.padData(buttons: 1 << 13)))])
    await waitUntil("input reconnects only the paired controller") {
      await manager.connectedLogicalControllerIDs() == [slot]
    }
    #expect(await manager.activeLogicalControllerIDs() == [slot])
    await waitUntil("the paired controller activates output again") {
      dispatcher.activations == [slot, slot]
    }
    let suspended = await manager.suspendController(.model(slot.model))
    #expect(suspended.state == .suspended)
    await manager.stop()
  }

  @Test
  func repeatedStopEndsTheControllerOnce() async {
    // An admission rollback may stop a pipeline a racing detach already stopped.
    let dispatcher = ReceiverSlotDispatcher()
    let pipeline = DevicePipeline(
      identifier: slotIdentifiers[0],
      transport: .usb(device: ReceiverSlotProvider.device),
      driver: XUSBDriver(isWirelessReceiver: true),
      dispatcher: dispatcher
    )

    await pipeline.stop()
    await pipeline.stop()

    #expect(dispatcher.stops == [slotIdentifiers[0]])
  }

  private func slotSessions(
    reads: (UInt8) -> [Result<[UInt8], USBTransportError>]
  ) -> [UInt8: RecoveryUSBSession] {
    Dictionary(
      uniqueKeysWithValues: ReceiverSlotProvider.slotInterfaces.map {
        ($0, RecoveryUSBSession(readResults: reads($0), readError: .timeout))
      }
    )
  }

  private func ledPacket(_ pattern: UInt8) -> [UInt8] {
    [0x00, 0x00, 0x08, pattern] + [UInt8](repeating: 0, count: 8)
  }

  private func makeManager(_ provider: ReceiverSlotProvider) -> DeviceManager {
    DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
  }
}
