#if DEBUG
  import Foundation
  import OpenJoystickDriverUSB

  struct PassiveUSBCommand {
    func run(arguments: [String]) throws {
      guard arguments.count == 4, arguments[0] == "--vid", arguments[2] == "--pid",
        let vendorID = UInt16(arguments[1], radix: 16),
        let productID = UInt16(arguments[3], radix: 16)
      else { throw CLIParseError.unexpectedArguments(command: "diagnose usb-passive") }
      let tuple = PassiveUSBDescriptorTuple(vendorID: vendorID, productID: productID)
      let facts: PassiveUSBProbeResult
      if let failure = ProcessInfo.processInfo.environment["OJD_PASSIVE_USB_TEST_FAILURE"] {
        let source = DeterministicPassiveUSBSource(failure: failure)
        facts = try PassiveUSBDescriptorProbe.scanUsingContributorSource(
          authorizedTuple: tuple,
          source: source
        )
      } else {
        facts = try PassiveUSBDescriptorProbe.scan(authorizedTuple: tuple)
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.keyEncodingStrategy = .convertToSnakeCase
      let data = try encoder.encode(facts)
      guard let output = String(data: data, encoding: .utf8) else {
        throw EncodingError.invalidValue(
          data,
          .init(codingPath: [], debugDescription: "UTF-8 encoding failed")
        )
      }
      print(output)
    }
  }

  private struct DeterministicPassiveUSBSource: PassiveUSBRegistrySource {
    let failure: String

    func matchingServices(className: String, numericProperties: [String: UInt64]) throws
      -> [PassiveUSBRegistryNode]
    {
      switch failure {
      case "zero": return []
      case "multiple":
        return [
          PassiveUSBRegistryNode(serviceClass: className, properties: [:]),
          PassiveUSBRegistryNode(serviceClass: className, properties: [:])
        ]
      case "matching-failure": throw PassiveUSBDescriptorProbeError.matchingFailed(-536_870_181)
      default: throw PassiveUSBDescriptorProbeError.matchingFailed(-1)
      }
    }
  }
#endif
