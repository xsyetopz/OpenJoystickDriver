import Testing

@testable import OpenJoystickDriverKit

/// The extension layouts of `nintendo-wii.json` applied to the recorded data samples.
@Suite
struct WiiExtensionLayoutTests {
  private typealias Remote = ProtocolDescription.WiiRemote

  private static func layout(_ kind: String) throws -> Remote.ExtensionLayout {
    let wii = try #require(PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote)
    return try #require(wii.extensions.first { $0.kind == kind }?.layout)
  }

  private static func sample(_ name: String) throws -> [UInt8] {
    Array(try WiiFixtureFolder.extensions.bytes(name))
  }

  private static func raw(
    _ layout: Remote.ExtensionLayout,
    _ control: Control,
    _ name: String
  )
    throws -> Int
  {
    let data = try sample(name)
    let field = try #require(layout.sticks.first { $0.control == control }?.field)
    return field.value(in: data)
  }

  @Test
  func nunchukSticksAndAccelerometerReassembleFromTheirBytes() throws {
    let layout = try Self.layout("Nunchuk")
    #expect(layout.stickCenter == .firstSample)
    #expect(try Self.raw(layout, .leftStickX, "data-nunchuk-high") == 228)
    #expect(try Self.raw(layout, .leftStickY, "data-nunchuk-low") == 27)
    let accelerometer = try #require(layout.accelerometer)
    #expect(accelerometer.x.value(in: try Self.sample("data-nunchuk-rest")) == 512)
    #expect(accelerometer.z.value(in: try Self.sample("data-nunchuk-high")) == 1023)
  }

  @Test
  func nunchukButtonsAreDownWhenTheirBitIsClear() throws {
    let layout = try Self.layout("Nunchuk")
    let z = try #require(layout.buttons.first { $0.control == .leftTrigger })
    #expect(!z.pressedWhenSet)
    #expect(try Self.sample("data-nunchuk-low")[z.field.byte] & z.field.mask == 0)
    #expect(try Self.sample("data-nunchuk-rest")[z.field.byte] & z.field.mask != 0)
  }

  @Test
  func classicSplitFieldsReassembleFiveBitValues() throws {
    let layout = try Self.layout("ClassicController")
    #expect(try Self.raw(layout, .leftStickX, "data-classic-rest") == 32)
    #expect(try Self.raw(layout, .rightStickX, "data-classic-rest") == 16)
    #expect(try Self.raw(layout, .rightStickX, "data-classic-high") == 31)
    #expect(try Self.raw(layout, .rightStickY, "data-classic-high") == 31)
    let trigger = try #require(layout.triggers.first { $0.control == .leftTrigger })
    #expect(trigger.field.bits == 5)
    #expect(trigger.field.value(in: try Self.sample("data-classic-high")) == 31)
    #expect(trigger.field.value(in: try Self.sample("data-classic-low")) == 0)
  }

  @Test
  func classicAIsEastAndProSharesLayout() throws {
    let layout = try Self.layout("ClassicController")
    let east = try #require(layout.buttons.first { $0.control == .east })
    #expect(east.field == .init(byte: 5, mask: 0x10))
    #expect(try Self.layout("ClassicControllerPro") == layout)
  }
}
