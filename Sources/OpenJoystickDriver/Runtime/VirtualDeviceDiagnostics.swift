import CoreHID
import Foundation
import GameController
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

enum VirtualDeviceDiagnostics {
  static func enumerateHIDGamepads() async -> [ApplicationServiceHIDGamepadSnapshot] {
    if #available(macOS 15, *) { return await CoreHIDVirtualDeviceDiagnostics.enumerate() }
    return IOHIDVirtualDeviceDiagnostics.enumerate()
  }

}

@available(macOS, introduced: 10.15, obsoleted: 15.0) private enum IOHIDVirtualDeviceDiagnostics {
  private static let ioUserClassKey = "IOUserClass"

  static func enumerate() -> [ApplicationServiceHIDGamepadSnapshot] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
      print("[VirtualDeviceDiagnostics] IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
    }

    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    let snapshots = devices.compactMap(snapshot).sorted(by: snapshotOrder)
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    return snapshots
  }

  private static func snapshot(_ device: IOHIDDevice) -> ApplicationServiceHIDGamepadSnapshot? {
    let location = intProp(device, kIOHIDLocationIDKey)
    let serial = strProp(device, kIOHIDSerialNumberKey)
    let isOJD =
      UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
      || ((UInt32(truncatingIfNeeded: location) & 0xFFFF_0000)
        == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace)
    guard isOJD || looksLikeGamepad(device) else { return nil }

    return ApplicationServiceHIDGamepadSnapshot(
      vendorID: UInt16(truncatingIfNeeded: intProp(device, kIOHIDVendorIDKey)),
      productID: UInt16(truncatingIfNeeded: intProp(device, kIOHIDProductIDKey)),
      product: strProp(device, kIOHIDProductKey),
      transport: strProp(device, kIOHIDTransportKey),
      locationID: location == 0 ? nil : UInt32(truncatingIfNeeded: location),
      serialKind: serialKind(serial),
      ioUserClass: IOHIDDeviceGetProperty(device, ioUserClassKey as CFString) as? String,
      isOJDUserSpace: isOJD,
      isGameControllerSupported: {
        if #available(macOS 11.0, *) { return GCController.supportsHIDDevice(device) }
        return nil
      }()
    )
  }

  private static func looksLikeGamepad(_ device: IOHIDDevice) -> Bool {
    let primaryPage = intProp(device, kIOHIDPrimaryUsagePageKey)
    let primaryUsage = intProp(device, kIOHIDPrimaryUsageKey)
    if primaryPage == kHIDPage_GenericDesktop && primaryUsage == kHIDUsage_GD_GamePad {
      return true
    }
    guard
      let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
        as? [[String: Any]]
    else { return false }
    return pairs.contains { pair in
      let page = pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0
      let usage = pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
      return page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_GamePad
    }
  }

  private static func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  private static func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
  }
}

@available(macOS 15, *) private enum CoreHIDVirtualDeviceDiagnostics {
  static func enumerate() async -> [ApplicationServiceHIDGamepadSnapshot] {
    let collector = SnapshotCollector()
    let manager = HIDDeviceManager()
    let task = Task {
      let criteria = [
        HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.gamepad)),
        HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.joystick)),
        HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.multiAxisController))
      ]
      do {
        for try await notification in await manager.monitorNotifications(matchingCriteria: criteria)
        {
          if Task.isCancelled { break }
          guard case .deviceMatched(let reference) = notification,
            let client = HIDDeviceClient(deviceReference: reference)
          else { continue }
          await collector.insert(snapshot: snapshot(client))
        }
      } catch {}
    }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    return await collector.snapshot().sorted(by: snapshotOrder)
  }

  private static func snapshot(_ client: HIDDeviceClient) async
    -> ApplicationServiceHIDGamepadSnapshot
  {
    let serial = await client.serialNumber
    let location = await client.locationID
    return ApplicationServiceHIDGamepadSnapshot(
      vendorID: UInt16(truncatingIfNeeded: await client.vendorID),
      productID: UInt16(truncatingIfNeeded: await client.productID),
      product: await client.product,
      transport: transportName(await client.transport),
      locationID: location.map { UInt32(truncatingIfNeeded: $0) },
      serialKind: serialKind(serial),
      ioUserClass: nil,
      isOJDUserSpace: UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial),
      isGameControllerSupported: nil
    )
  }

  private static func transportName(_ transport: HIDDeviceTransport?) -> String? {
    guard let transport else { return nil }
    return switch transport {
    case .usb: "USB"
    case .bluetooth: "Bluetooth"
    case .bluetoothLowEnergy: "Bluetooth Low Energy"
    case .bluetoothAACP: "Bluetooth AACP"
    case .aid: "AID"
    case .i2c: "I2C"
    case .spi: "SPI"
    case .serial: "Serial"
    case .iap: "iAP"
    case .airPlay: "AirPlay"
    case .spu: "SPU"
    case .fifo: "FIFO"
    case .inductiveInBand: "Inductive In-Band"
    case .virtual: "Virtual"
    case .unknown(let value): value
    @unknown default: nil
    }
  }

  private actor SnapshotCollector {
    private var values: [UInt64: ApplicationServiceHIDGamepadSnapshot] = [:]

    func insert(snapshot: ApplicationServiceHIDGamepadSnapshot) {
      let key =
        UInt64(snapshot.vendorID) << 48 | UInt64(snapshot.productID) << 32
        | UInt64(snapshot.locationID ?? 0)
      values[key] = snapshot
    }

    func snapshot() -> [ApplicationServiceHIDGamepadSnapshot] { Array(values.values) }
  }
}

private func serialKind(_ serial: String?) -> ApplicationServiceSerialKind {
  guard let serial, !serial.isEmpty else { return .none }
  return UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) ? .ojdUserSpace : .present
}

private func snapshotOrder(
  _ lhs: ApplicationServiceHIDGamepadSnapshot,
  _ rhs: ApplicationServiceHIDGamepadSnapshot
) -> Bool {
  if lhs.isOJDUserSpace != rhs.isOJDUserSpace { return lhs.isOJDUserSpace && !rhs.isOJDUserSpace }
  if lhs.vendorID != rhs.vendorID { return lhs.vendorID < rhs.vendorID }
  return lhs.productID < rhs.productID
}
