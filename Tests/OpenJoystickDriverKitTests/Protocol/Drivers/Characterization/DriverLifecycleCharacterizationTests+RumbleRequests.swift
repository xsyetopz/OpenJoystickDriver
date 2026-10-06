import Foundation
import Testing

@testable import OpenJoystickDriverKit

// All-zero rumble and rumble channel subsets, encoded by today's drivers.
extension DriverLifecycleCharacterizationTests {
  /// All-zero rumble at 0 ms for the first ten subjects.
  @Test
  func allZeroRumblePlans1() throws {
    #expect(
      try zeroRumbleLines(Self.namedSubjects[0..<10]) == [
        "gipUSB off [leftMain,leftTrigger,rightMain,rightTrigger]", "  plan interval=0 reports=1",
        "  ep=0x01 timeout=2000 n=13", "    09000109000f00000000ff00ff",
        "gipKeepAliveDisabled off [leftMain,leftTrigger,rightMain,rightTrigger]",
        "  plan interval=0 reports=1", "  ep=0x07 timeout=2000 n=13",
        "    09000109000f00000000ff00ff", "xidGamepad off [leftMain,rightMain]",
        "  plan interval=0 reports=1", "  ep=0x02 timeout=2000 n=6", "    000600000000",
        "xusbWired off [leftMain,rightMain]", "  plan interval=0 reports=1",
        "  ep=0x01 timeout=2000 n=8", "    0008000000000000",
        "xusbReceiver off [leftMain,rightMain]", "  plan interval=0 reports=1",
        "  ep=0x01 timeout=2000 n=12", "    00010fc00000000000000000",
        "sixaxisUSB off [leftMain,rightMain]", "  plan interval=0 reports=1", "  id=0x01 n=49",
        "    0101ff00ff000000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "sixaxisBluetooth off [leftMain,rightMain]",
        "  plan interval=0 reports=1", "  id=0x01 n=49",
        "    0101ff00ff000000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "dualShock4USB off [leftMain,rightMain]",
        "  plan interval=0 reports=1", "  id=0x05 n=32",
        "    0501000000000000000000000000000000000000000000000000000000000000",
        "dualShock4Bluetooth off [leftMain,rightMain]", "  plan interval=0 reports=1",
        "  id=0x11 n=78", "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89", "dualSenseUSB off [leftMain,rightMain]",
        "  plan interval=0 reports=1", "  id=0x02 n=63",
        "    0203000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  /// All-zero rumble at 0 ms for the other subjects; Steam encodes no haptic report.
  @Test
  func allZeroRumblePlans2() throws {
    #expect(
      try zeroRumbleLines(Self.namedSubjects[10..<20]) == [
        "dualSenseBluetooth off [leftMain,rightMain]", "  plan interval=0 reports=1",
        "  id=0x31 n=78", "    3100100300000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000cc642e96", "switchUSB off [leftMain,rightMain]",
        "  plan interval=0 reports=1", "  id=0x10 n=10", "    10000001404000014040",
        "switchBluetooth off [leftMain,rightMain]", "  plan interval=0 reports=1", "  id=0x10 n=10",
        "    10000001404000014040", "steamWired off [leftHaptic,rightHaptic]",
        "  plan interval=0 reports=0", "steamDongle off [leftHaptic,rightHaptic]",
        "  plan interval=0 reports=0", "gameSirUSB off []", "  plan interval=0 reports=1",
        "  id=0x0f n=64", "    0f20665500000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "gameSirEnhancedHID off [leftMain,rightMain]", "  plan interval=0 reports=1",
        "  id=0x0f n=64", "    0f20665500000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "gameSirEnhancedHID8K off [leftMain,rightMain]", "  plan interval=0 reports=1",
        "  id=0x0f n=64", "    0f20665500000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  /// GIP trigger-only and main-only rumble.
  @Test
  func gipTriggerOnlyAndMainOnlyRumble() throws {
    #expect(
      try gipChannelSubsetLines() == [
        "triggers", "  plan interval=0 reports=1", "  ep=0x01 timeout=2000 n=13",
        "    09000109000f20100000ff00ff", "main", "  plan interval=0 reports=1",
        "  ep=0x01 timeout=2000 n=13", "    09000109000f00004080ff00ff",
      ]
    )
  }

  /// Trigger channels alone reach DS4 and Switch as all-zero motors.
  @Test
  func dualShock4AndSwitchDropTriggerRumble() throws {
    #expect(
      try droppedTriggerChannelLines() == [
        "dualShock4USB", "  plan interval=0 reports=1", "  id=0x05 n=32",
        "    0501000000000000000000000000000000000000000000000000000000000000",
        "dualShock4Bluetooth", "  plan interval=0 reports=1", "  id=0x11 n=78",
        "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89", "switchUSB", "  plan interval=0 reports=1",
        "  id=0x10 n=10", "    10000001404000014040", "switchBluetooth",
        "  plan interval=0 reports=1", "  id=0x10 n=10", "    10000001404000014040",
      ]
    )
  }

  /// Each Joy-Con encodes only its own side.
  @Test
  func joyConRumbleDrivesOnlyItsOwnSide() throws {
    #expect(
      try joyConSideLines() == [
        "joyCon[left] [leftMain]", "  plan interval=0 reports=1", "  id=0x10 n=10",
        "    10000049405200014040", "joyCon[right] [rightMain]", "  plan interval=0 reports=1",
        "  id=0x10 n=10", "    100000014040008bc063",
      ]
    )
  }
}
