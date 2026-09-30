import Foundation
import OpenJoystickDriverUSB

/// Prints the passive descriptor facts for one authorized USB device as JSON and returns the
/// exit status.
func runPassiveUSBProbe(vendorID: UInt16, productID: UInt16) -> Int32 {
  let tuple = PassiveUSBDescriptorTuple(vendorID: vendorID, productID: productID)
  do {
    let facts = try PassiveUSBDescriptorProbe.scan(authorizedTuple: tuple)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    print(String(bytes: try encoder.encode(facts), encoding: .utf8) ?? "")
    return 0
  } catch {
    fputs("ERROR: passive USB probe failed: \(error)\n", stderr)
    return 1
  }
}
