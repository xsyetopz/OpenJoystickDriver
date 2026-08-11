import SwiftUSB
import Testing

@testable import OpenJoystickDriverKit

struct USBStartupOutputPolicyTests {
  @Test func ignoresIOErrorForXbox360RingLED() {
    let parser = Xbox360Parser()
    let error = USBError(code: USBError.errorIO, log: false)

    #expect(
      isIgnorableUSBStartupOutputError(parser: parser, packet: [0x01, 0x03, 0x06], error: error)
    )
  }

  @Test func preservesOtherXbox360StartupOutputFailures() {
    let parser = Xbox360Parser()
    let errors = [
      USBError.errorNoDevice, USBError.errorAccess, USBError.errorTimeout, USBError.errorPipe,
    ]

    for code in errors {
      let error = USBError(code: code, log: false)
      #expect(
        !isIgnorableUSBStartupOutputError(parser: parser, packet: [0x01, 0x03, 0x06], error: error)
      )
    }
  }

  @Test func preservesIOErrorForOtherStartupPacketsAndParsers() {
    let parser = Xbox360Parser()
    let genericParser = GenericHIDParser(identifier: DeviceIdentifier(vendorID: 1, productID: 2))
    let error = USBError(code: USBError.errorIO, log: false)

    #expect(!isIgnorableUSBStartupOutputError(parser: parser, packet: [0x00, 0x01], error: error))
    #expect(
      !isIgnorableUSBStartupOutputError(
        parser: genericParser,
        packet: [0x01, 0x03, 0x06],
        error: error
      )
    )
  }
}
