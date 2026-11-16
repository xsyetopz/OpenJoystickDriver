import CoreBluetooth
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

final class Lister: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  var central: CBCentralManager?
  var peripherals: [CBPeripheral] = []

  override init() {
    super.init()
    central = CBCentralManager(delegate: self, queue: nil)
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    print("state \(central.state.rawValue) authorization \(CBManager.authorization.rawValue)")
    guard central.state == .poweredOn else { return }
    let services = ["1812", "180A", "180F"].map { CBUUID(string: $0) }
    peripherals = central.retrieveConnectedPeripherals(withServices: services)
    for peripheral in peripherals {
      print("peripheral \(peripheral.name ?? "?") \(peripheral.identifier)")
      peripheral.delegate = self
      central.connect(peripheral)
    }
    if peripherals.isEmpty { print("no connected peripherals") }
  }

  func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.discoverServices(nil)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: Error?) {
    for service in peripheral.services ?? [] {
      print("\(peripheral.name ?? "?") service \(service.uuid)")
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error _: Error?
  ) {
    for characteristic in service.characteristics ?? [] {
      let name = peripheral.name ?? "?"
      let properties = String(characteristic.properties.rawValue, radix: 16)
      print("\(name) \(service.uuid) char \(characteristic.uuid) props=0x\(properties)")
    }
  }
}

let lister = Lister()
RunLoop.main.run(
  until: Date().addingTimeInterval(Double(CommandLine.arguments.dropFirst().first ?? "8") ?? 8)
)
print("end")
