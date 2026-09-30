import CoreBluetooth
import Foundation
import OpenJoystickDriverKit

/// Connects Switch 2 controllers that advertise in sync mode and feeds their GATT link to the hub.
///
/// Every CoreBluetooth call and delegate callback runs on one serial queue, so input keeps its
/// order. The central never reads an encrypted characteristic: an SMP pairing attempt makes the
/// controller disconnect.
final class Switch2BluetoothLECentral: NSObject, @unchecked Sendable {
  private struct Link {
    let peripheral: CBPeripheral
    let productID: UInt16
    let name: String?
    var input: CBCharacteristic?
    var command: CBCharacteristic?
    var reply: CBCharacteristic?
    var vibration: CBCharacteristic?
    var admitted = false
  }

  private let hub: Switch2BluetoothLEHub
  private let queue = DispatchQueue(label: "com.openjoystickdriver.switch2-bluetooth-le")
  private var central: CBCentralManager?
  private var links: [UUID: Link] = [:]

  private let serviceUUID = CBUUID(string: Switch2BluetoothLEProfile.serviceUUID)
  private let inputUUID = CBUUID(string: Switch2BluetoothLEProfile.inputUUID)
  private let commandUUID = CBUUID(string: Switch2BluetoothLEProfile.commandUUID)
  private let replyUUID = CBUUID(string: Switch2BluetoothLEProfile.commandReplyUUID)

  init(hub: Switch2BluetoothLEHub) { self.hub = hub }

  /// Creates the central, which asks for Bluetooth access on first use.
  func start() {
    queue.async {
      guard self.central == nil else { return }
      self.central = CBCentralManager(delegate: self, queue: self.queue)
    }
  }

  func stop() {
    queue.sync {
      central?.stopScan()
      for link in links.values { central?.cancelPeripheralConnection(link.peripheral) }
      for id in links.keys { hub.linkDisconnected(peripheralID: id) }
      links.removeAll()
      central?.delegate = nil
      central = nil
    }
  }

  /// Restarts the scan, because a scan that filters duplicates does not report a peripheral it
  /// already reported, even after that peripheral disconnects and advertises again.
  private func scan() {
    guard let central, central.state == .poweredOn else { return }
    central.stopScan()
    central.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
  }

  private func drop(_ peripheral: CBPeripheral) {
    guard links.removeValue(forKey: peripheral.identifier) != nil else { return }
    hub.linkDisconnected(peripheralID: peripheral.identifier)
    central?.cancelPeripheralConnection(peripheral)
    scan()
  }
}

extension Switch2BluetoothLECentral: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central.state == .poweredOn else {
      for id in links.keys { hub.linkDisconnected(peripheralID: id) }
      links.removeAll()
      return
    }
    scan()
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    // swiftlint:disable:next legacy_objc_type
    rssi RSSI: NSNumber
  ) {
    guard links[peripheral.identifier] == nil,
      let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
      let productID = Switch2BluetoothLEProfile.productID(manufacturerData: data)
    else { return }
    let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
    links[peripheral.identifier] = Link(peripheral: peripheral, productID: productID, name: name)
    central.connect(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.delegate = self
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: (any Error)?
  ) { drop(peripheral) }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: (any Error)?
  ) { drop(peripheral) }
}

extension Switch2BluetoothLECentral: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
    guard let link = links[peripheral.identifier],
      let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
      let vibration = Switch2BluetoothLEProfile.vibrationUUIDs[link.productID]
    else {
      drop(peripheral)
      return
    }
    peripheral.discoverCharacteristics(
      [inputUUID, commandUUID, replyUUID, CBUUID(string: vibration)],
      for: service
    )
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: (any Error)?
  ) {
    guard var link = links[peripheral.identifier],
      let vibrationUUID = Switch2BluetoothLEProfile.vibrationUUIDs[link.productID]
    else {
      drop(peripheral)
      return
    }
    let characteristics = service.characteristics ?? []
    func find(_ uuid: CBUUID) -> CBCharacteristic? { characteristics.first { $0.uuid == uuid } }
    link.input = find(inputUUID)
    link.command = find(commandUUID)
    link.reply = find(replyUUID)
    link.vibration = find(CBUUID(string: vibrationUUID))
    guard let input = link.input, let reply = link.reply, link.command != nil, link.vibration != nil
    else {
      drop(peripheral)
      return
    }
    links[peripheral.identifier] = link
    peripheral.setNotifyValue(true, for: input)
    peripheral.setNotifyValue(true, for: reply)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: (any Error)?
  ) {
    guard error == nil, var link = links[peripheral.identifier] else {
      drop(peripheral)
      return
    }
    guard !link.admitted, link.input?.isNotifying == true, link.reply?.isNotifying == true,
      let command = link.command, let vibration = link.vibration
    else { return }
    link.admitted = true
    links[peripheral.identifier] = link
    hub.linkConnected(
      peripheralID: peripheral.identifier,
      productID: link.productID,
      productName: link.name,
      writer: Writer(queue: queue, peripheral: peripheral, command: command, vibration: vibration)
    )
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: (any Error)?
  ) {
    guard error == nil, let link = links[peripheral.identifier], link.admitted,
      let value = characteristic.value
    else { return }
    if characteristic.uuid == inputUUID {
      hub.receivedInput(peripheralID: peripheral.identifier, bytes: [UInt8](value))
    } else if characteristic.uuid == replyUUID {
      hub.receivedReply(peripheralID: peripheral.identifier, bytes: [UInt8](value))
    }
  }
}

extension Switch2BluetoothLECentral {
  /// Writes without response on the central's queue. Callers are pipeline tasks, never that queue.
  private struct Writer: Switch2BluetoothLEWriter, @unchecked Sendable {
    let queue: DispatchQueue
    let peripheral: CBPeripheral
    let command: CBCharacteristic
    let vibration: CBCharacteristic

    func writeCommand(_ bytes: [UInt8]) -> Bool { write(bytes, to: command) }
    func writeVibration(_ bytes: [UInt8]) -> Bool { write(bytes, to: vibration) }

    private func write(_ bytes: [UInt8], to characteristic: CBCharacteristic) -> Bool {
      queue.sync {
        guard peripheral.state == .connected,
          bytes.count <= peripheral.maximumWriteValueLength(for: .withoutResponse)
        else { return false }
        peripheral.writeValue(Data(bytes), for: characteristic, type: .withoutResponse)
        return true
      }
    }
  }
}
