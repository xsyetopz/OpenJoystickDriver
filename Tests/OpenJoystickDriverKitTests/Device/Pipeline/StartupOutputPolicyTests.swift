import Testing

@testable import OpenJoystickDriverKit

struct USBStartupOutputPolicyTests {
  @Test func ignoresIOErrorForXbox360RingLED() {
    let parser = Xbox360Parser()
    let error = USBTransportError.inputOutput

    #expect(
      isIgnorableUSBStartupOutputError(parser: parser, packet: [0x01, 0x03, 0x06], error: error)
    )
  }

  @Test func ignoresUnsupportedErrorForXbox360RingLED() {
    let parser = Xbox360Parser()

    #expect(
      isIgnorableUSBStartupOutputError(
        parser: parser,
        packet: [0x01, 0x03, 0x06],
        error: .notSupported
      )
    )
  }

  @Test func ignoresMissingOutputPipeForXbox360RingLED() {
    let parser = Xbox360Parser()

    #expect(
      isIgnorableUSBStartupOutputError(
        parser: parser,
        packet: [0x01, 0x03, 0x06],
        error: .notFound
      )
    )
  }

  @Test func preservesOtherXbox360StartupOutputFailures() {
    let parser = Xbox360Parser()
    let errors: [USBTransportError] = [
      .disconnected, .accessDenied, .timeout, .platform(code: 1, message: "unexpected")
    ]

    for error in errors {
      #expect(
        !isIgnorableUSBStartupOutputError(parser: parser, packet: [0x01, 0x03, 0x06], error: error)
      )
    }
  }

  @Test func preservesIOErrorForOtherStartupPacketsAndParsers() {
    let parser = Xbox360Parser()
    let genericParser = GenericHIDParser(identifier: DeviceIdentifier(vendorID: 1, productID: 2))
    let error = USBTransportError.inputOutput

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
