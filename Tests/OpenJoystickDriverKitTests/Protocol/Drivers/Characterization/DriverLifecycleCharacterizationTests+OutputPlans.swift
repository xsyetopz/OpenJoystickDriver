import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Stateful encoders across commands, Steam durations, and GameSir readiness gates.
extension DriverLifecycleCharacterizationTests {
  /// The Switch 0x30 subcommand embeds the last rumble data.
  @Test
  func switchUSBPlayerEmbedsLastRumble() throws {
    #expect(
      try rumbleThenPlayerLines(Self.switchUSB) == [
        "rumble", "  plan interval=0 reports=1", "  id=0x10 n=10", "    100000494052008bc063",
        "player[player2]", "  plan interval=0 reports=1", "  id=0x01 n=12",
        "    010100494052008bc0633003",
      ]
    )
  }

  /// The Switch 0x30 subcommand embeds the last rumble data.
  @Test
  func switchBluetoothPlayerEmbedsLastRumble() throws {
    #expect(
      try rumbleThenPlayerLines(Self.switchBluetooth) == [
        "rumble", "  plan interval=0 reports=1", "  id=0x10 n=10", "    100000494052008bc063",
        "player[player2]", "  plan interval=0 reports=1", "  id=0x01 n=12",
        "    010100494052008bc0633003",
      ]
    )
  }

  /// Sixaxis report 0x01 carries rumble and LEDs together.
  @Test
  func sixaxisUSBPlayerKeepsLastRumble() throws {
    #expect(
      try rumbleThenPlayerLines(Self.sixaxisUSB) == [
        "rumble", "  plan interval=0 reports=1", "  id=0x01 n=49",
        "    0101ff01ff400000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "player[player2]", "  plan interval=0 reports=1",
        "  id=0x01 n=49", "    0101ff01ff400000000004ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000",
      ]
    )
  }

  /// Sixaxis report 0x01 carries rumble and LEDs together.
  @Test
  func sixaxisBluetoothPlayerKeepsLastRumble() throws {
    #expect(
      try rumbleThenPlayerLines(Self.sixaxisBluetooth) == [
        "rumble", "  plan interval=0 reports=1", "  id=0x01 n=49",
        "    0101ff01ff400000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "player[player2]", "  plan interval=0 reports=1",
        "  id=0x01 n=49", "    0101ff01ff400000000004ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000",
      ]
    )
  }

  /// Each DualSense Bluetooth report advances the sequence nibble.
  @Test
  func dualSenseBluetoothSequenceAdvancesPerReport() throws {
    #expect(
      try dualSenseBluetoothSequenceLines() == [
        "rumble", "  plan interval=0 reports=1", "  id=0x31 n=78",
        "    3100100300804000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000cbd1e087", "color", "  plan interval=0 reports=1",
        "  id=0x31 n=78", "    3110100004000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000001122330000000000000000000000000000",
        "    00000000000000000000da867396", "player[player2]", "  plan interval=0 reports=1",
        "  id=0x31 n=78", "    3120100010000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000a0000000000000000000000000000000000",
        "    00000000000000000000426f9c43",
      ]
    )
  }

  /// Each GIP rumble packet advances the sequence number.
  @Test
  func gipSequenceAdvancesPerRumble() throws {
    #expect(
      try gipTwoRumbleLines() == [
        "first", "  plan interval=0 reports=1", "  ep=0x01 timeout=2000 n=13",
        "    09000109000f20104080ff00ff", "second", "  plan interval=0 reports=1",
        "  ep=0x01 timeout=2000 n=13", "    09000209000f00004080ff00ff",
      ]
    )
  }

  /// Steam 0 ms encodes a 65 ms pulse; no logical controller encodes an empty plan.
  @Test
  func steamHapticDurations() throws {
    #expect(
      try steamDurationLines() == [
        "dongle ms=0", "  plan interval=0 reports=2", "  id=0x00 n=64",
        "    8f0801e8fd00000100f000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8f0800e8fd00000100f700000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "dongle ms=65",
        "  plan interval=0 reports=2", "  id=0x00 n=64",
        "    8f0801e8fd00000100f000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8f0800e8fd00000100f700000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "dongle ms=5000",
        "  plan interval=0 reports=2", "  id=0x00 n=64",
        "    8f0801ffff00004d00f000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8f0800ffff00004d00f700000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "dongle noController", "  plan interval=0 reports=0", "wired",
        "  plan interval=0 reports=2", "  id=0x00 n=64",
        "    8f0801e8fd00000100f000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8f0800e8fd00000100f700000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  /// GameSir USB colour and brightness per readiness stage.
  @Test
  func gameSirUSBLightingReadiness() throws {
    #expect(
      try gameSirReadinessLines(Self.gameSirUSB) == [
        "stage cold", "color", "  nil", "brightness[128]", "  nil", "stage slotOnly", "color",
        "  nil", "brightness[128]", "  nil", "stage sessionOnly", "color", "  nil",
        "brightness[128]", "  plan interval=0 reports=1", "  ep=0x02 timeout=2000 n=64",
        "    0f00013c032001f9013200000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "stage ready",
        "color", "  nil", "brightness[128]", "  plan interval=0 reports=1",
        "  ep=0x02 timeout=2000 n=64",
        "    0f00013c032001f9013200000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  /// GameSir lighting-slot colour and brightness per readiness stage.
  @Test
  func gameSirEnhancedLightingReadiness() throws {
    #expect(
      try gameSirReadinessLines(Self.gameSirEnhancedHID) == [
        "stage cold", "color", "  nil", "brightness[128]", "  nil", "stage slotOnly", "color",
        "  nil", "brightness[128]", "  nil", "stage sessionOnly", "color", "  nil",
        "brightness[128]", "  nil", "stage ready", "color", "  plan interval=20000000 reports=4",
        "  id=0x0f n=64", "    0f032000f9300105146411223311223311223311223311223311223311223311",
        "    2233112233112233112233112233112233112233112200000000000000000000", "  id=0x0f n=64",
        "    0f03200129303311223311223311223311223311223311223311223311223311",
        "    2233112233112233112233112233112233112233112200000000000000000000", "  id=0x0f n=64",
        "    0f032001591c3311223311223311223311223311223311223311223311223311",
        "    2233000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f03200000010200000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "brightness[128]",
        "  plan interval=0 reports=1", "  id=0x0f n=64",
        "    0f032000fc013200000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  /// GameSir 8K colour and brightness per readiness stage.
  @Test
  func gameSirEnhanced8KLightingReadiness() throws {
    #expect(
      try gameSirReadinessLines(Self.gameSirEnhancedHID8K) == [
        "stage cold", "color", "  nil", "brightness[128]", "  nil", "stage slotOnly", "color",
        "  nil", "brightness[128]", "  nil", "stage sessionOnly", "color",
        "  plan interval=20000000 reports=4", "  id=0x0f n=64",
        "    0f0320000c0300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000100300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000140300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000180300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "brightness[128]",
        "  plan interval=0 reports=1", "  id=0x0f n=64",
        "    0f03200001013200000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "stage ready",
        "color", "  plan interval=20000000 reports=4", "  id=0x0f n=64",
        "    0f0320000c0300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000100300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000140300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000180300d2430000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "brightness[128]",
        "  plan interval=0 reports=1", "  id=0x0f n=64",
        "    0f03200001013200000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }
}
