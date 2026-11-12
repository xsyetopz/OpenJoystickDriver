import CoreBluetooth
import Foundation
import OpenJoystickDriverKit

/// Connects Switch 2 controllers that advertise in sync mode and feeds their GATT link to the hub.
///
/// Every CoreBluetooth call and delegate callback runs on one serial queue, so input keeps its
/// order. The central never reads an encrypted characteristic: an SMP pairing attempt makes the
/// controller disconnect.
final class Switch2BluetoothLECentral: NSObject, @unchecked Sendable {
  /// A discovered controller and the characteristics of its GATT link.
  private struct Link {
    /// The peripheral of the controller.
    let peripheral: CBPeripheral
    /// The product ID that the advertisement reports.
    let productID: UInt16
    /// The name that the advertisement or the peripheral reports.
    let name: String?
    /// The characteristic that notifies input reports.
    var input: CBCharacteristic?
    /// The characteristic that takes commands.
    var command: CBCharacteristic?
    /// The characteristic that notifies command replies.
    var reply: CBCharacteristic?
    /// The characteristic that takes vibration writes.
    var vibration: CBCharacteristic?
    /// The link that the hub reads once the notifications are on.
    var gatt: GATTPeripheralLink?
  }

  /// The hub that receives the GATT links.
  private let hub: Switch2BluetoothLEHub
  /// The serial queue of every CoreBluetooth call and callback.
  private let queue = DispatchQueue(label: "com.openjoystickdriver.switch2-bluetooth-le")
  /// The central manager; nil until ``start()`` or ``requestAccessAndStart()`` creates it, and
  /// after ``stop()``.
  private var central: CBCentralManager?
  /// The discovered controllers by peripheral identifier.
  private var links: [UUID: Link] = [:]

  /// The UUID of the controller's GATT service.
  private let serviceUUID = CBUUID(string: Switch2BluetoothLEProfile.serviceUUID)
  /// The UUID of the input characteristic.
  private let inputUUID = CBUUID(string: Switch2BluetoothLEProfile.inputUUID)
  /// The UUID of the command characteristic.
  private let commandUUID = CBUUID(string: Switch2BluetoothLEProfile.commandUUID)
  /// The UUID of the command reply characteristic.
  private let replyUUID = CBUUID(string: Switch2BluetoothLEProfile.commandReplyUUID)

  /// Reads the Bluetooth authorization without showing a prompt.
  private let authorization: @Sendable () -> CBManagerAuthorization
  /// Creates the central manager, which shows the Bluetooth prompt; nil creates none.
  private let makeManager:
    @Sendable (any CBCentralManagerDelegate, DispatchQueue) -> CBCentralManager?

  /// Creates a central that feeds `hub`.
  ///
  /// - Parameters:
  ///   - hub: The hub that receives the GATT links.
  ///   - authorization: Reads the Bluetooth authorization; the system's shows no prompt.
  ///   - makeManager: Creates the central manager; defaults to `CBCentralManager`.
  init(
    hub: Switch2BluetoothLEHub,
    authorization: @escaping @Sendable () -> CBManagerAuthorization = {
      CBCentralManager.authorization
    },
    makeManager:
      @escaping @Sendable (any CBCentralManagerDelegate, DispatchQueue) -> CBCentralManager? = {
        CBCentralManager(delegate: $0, queue: $1)
      }
  ) {
    self.hub = hub
    self.authorization = authorization
    self.makeManager = makeManager
  }

  /// Starts at app launch: creates the central only when Bluetooth access is already granted, so
  /// launch never shows the Bluetooth prompt.
  func start() {
    guard authorization() == .allowedAlways else { return }
    createCentral()
  }

  /// Creates the central from a user action, which asks for Bluetooth access when undecided.
  func requestAccessAndStart() { createCentral() }

  /// Creates the central once.
  private func createCentral() {
    queue.async {
      guard self.central == nil else { return }
      self.central = self.makeManager(self, self.queue)
    }
  }

  /// Stops scanning, disconnects every controller and releases the central manager.
  func stop() {
    queue.sync {
      central?.stopScan()
      for link in links.values { central?.cancelPeripheralConnection(link.peripheral) }
      for link in links.values { link.gatt?.disconnected() }
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

  /// Forgets the peripheral, disconnects it and scans again.
  private func drop(_ peripheral: CBPeripheral) {
    guard let link = links.removeValue(forKey: peripheral.identifier) else { return }
    link.gatt?.disconnected()
    central?.cancelPeripheralConnection(peripheral)
    scan()
  }
}

extension Switch2BluetoothLECentral: CBCentralManagerDelegate {
  /// Scans when Bluetooth powers on; otherwise drops every link.
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central.state == .poweredOn else {
      for link in links.values { link.gatt?.disconnected() }
      links.removeAll()
      return
    }
    scan()
  }

  /// Connects a peripheral whose advertisement carries Switch 2 manufacturer data.
  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    // swiftlint:disable:next legacy_objc_type
    rssi _: NSNumber
  ) {
    guard links[peripheral.identifier] == nil,
      let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
      let productID = Switch2BluetoothLEProfile.productID(manufacturerData: data)
    else { return }
    let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
    links[peripheral.identifier] = Link(peripheral: peripheral, productID: productID, name: name)
    central.connect(peripheral)
  }

  /// Discovers the GATT service of the connected peripheral.
  func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.delegate = self
    peripheral.discoverServices([serviceUUID])
  }

  /// Drops the peripheral that failed to connect.
  func centralManager(
    _: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error _: (any Error)?
  ) { drop(peripheral) }

  /// Drops the peripheral that disconnected.
  func centralManager(
    _: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error _: (any Error)?
  ) { drop(peripheral) }
}

extension Switch2BluetoothLECentral: CBPeripheralDelegate {
  /// Discovers the characteristics of the service, or drops a peripheral that lacks it.
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: (any Error)?) {
    guard let link = links[peripheral.identifier],
      let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
      let vibration = Switch2BluetoothLEProfile.vibrationUUID(productID: link.productID)
    else {
      drop(peripheral)
      return
    }
    peripheral.discoverCharacteristics(
      [inputUUID, commandUUID, replyUUID, CBUUID(string: vibration)],
      for: service
    )
  }

  /// Subscribes to the input and reply notifications once every characteristic is found, or drops
  /// the peripheral when one is missing.
  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error _: (any Error)?
  ) {
    guard var link = links[peripheral.identifier],
      let vibrationUUID = Switch2BluetoothLEProfile.vibrationUUID(productID: link.productID)
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

  /// Admits the GATT link to the hub once the input and reply notifications are on.
  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor _: CBCharacteristic,
    error: (any Error)?
  ) {
    guard error == nil, var link = links[peripheral.identifier] else {
      drop(peripheral)
      return
    }
    guard link.gatt == nil, link.input?.isNotifying == true, link.reply?.isNotifying == true,
      let command = link.command, let vibration = link.vibration,
      let gatt = GATTPeripheralLink(
        peripheral: CoreBluetoothGATTPeripheral(
          queue: queue,
          peripheral: peripheral,
          writable: [command, vibration]
        ),
        productID: link.productID,
        productName: link.name,
        hub: hub
      )
    else { return }
    link.gatt = gatt
    links[peripheral.identifier] = link
    gatt.admit()
  }

  /// Passes a notified value to the GATT link of the peripheral.
  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: (any Error)?
  ) {
    guard error == nil, let gatt = links[peripheral.identifier]?.gatt,
      let value = characteristic.value
    else { return }
    gatt.notified(characteristic: characteristic.uuid.uuidString, value: [UInt8](value))
  }
}

/// A ``GATTPeripheral`` over a connected `CBPeripheral`.
private struct CoreBluetoothGATTPeripheral: GATTPeripheral, @unchecked Sendable {
  /// The central's serial queue.
  let queue: DispatchQueue
  /// The peripheral to write to.
  let peripheral: CBPeripheral
  /// The characteristics that accept writes.
  let writable: [CBCharacteristic]

  /// The identifier of the peripheral.
  var identifier: UUID { peripheral.identifier }

  /// Writes `bytes` to the characteristic without response; false when the peripheral is not
  /// connected, the bytes exceed the write length, or the characteristic is not writable.
  func writeWithoutResponse(_ bytes: [UInt8], to characteristic: String) -> Bool {
    guard let target = writable.first(where: { $0.uuid.uuidString == characteristic.uppercased() })
    else { return false }
    return queue.sync {
      guard peripheral.state == .connected,
        bytes.count <= peripheral.maximumWriteValueLength(for: .withoutResponse)
      else { return false }
      peripheral.writeValue(Data(bytes), for: target, type: .withoutResponse)
      return true
    }
  }
}
