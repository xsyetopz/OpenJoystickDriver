import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Output ownership and native-pad gates through DeviceManager.
extension DriverLifecycleCharacterizationTests {
  /// Native Sixaxis drives rumble through report 0x01, which keeps the player LED; teardown
  /// stops the motors, then turns the LED off.
  @Test
  func nativeSixaxisDrivesRumbleThroughReport01() async throws {
    let row2 = "    0000000000000000000000000000000000"
    let stopped = "    0101ff00ff000000000002ff27100032ff27100032ff27100032ff2710003200"
    #expect(
      try await nativeSixaxisOutputSteps() == [
        "capabilities rumble=[leftMain,rightMain] lighting=[playerIndicator]", "rumble=true",
        "outputs=1", "  id=0x01 n=49",
        "    0101ff01ffff0000000002ff27100032ff27100032ff27100032ff2710003200", row2, "features=0",
        "stop=true", "outputs=1", "  id=0x01 n=49", stopped, row2, "features=0", "teardown",
        "outputs=2", "  id=0x01 n=49", stopped, row2, "  id=0x01 n=49",
        "    0101ff00ff000000000020ff27100032ff27100032ff27100032ff2710003200", row2, "features=0",
      ]
    )
  }

  /// Native DualShock 4 refuses every output and writes nothing.
  @Test
  func nativeDualShock4RefusesEveryOutput() async throws {
    #expect(
      try await nativeDualShock4OutputSteps() == [
        "capabilities rumble=[] lighting=[]", "rumble=false", "player=false", "color=false",
        "brightness=false", "mapping=false", "outputs=0", "features=0", "teardown", "outputs=0",
        "features=0",
      ]
    )
  }

  /// A manual stop-rumble leaves the active mapping rumble claim running, in one write.
  @Test
  func manualStopLeavesMappingRumbleRunning() async throws {
    #expect(
      try await stopUnderMappingClaimSteps() == [
        "mapping=true", "outputs=1", "  id=0x11 n=78",
        "    11c4000100000080000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000098dcb240", "features=0", "stop=true", "outputs=1",
        "  id=0x11 n=78", "    11c4000100000080000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000098dcb240", "features=0",
      ]
    )
  }

  /// Trigger channels are dropped; the main channels still drive DS4.
  @Test
  func manualTriggerRumbleStillDrivesDualShock4MainMotors() async throws {
    #expect(
      try await manualTriggerRumbleSteps() == [
        "rumble main=64,128 triggers=32,16 sent=true", "outputs=1", "  id=0x11 n=78",
        "    11c4000100008040000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000ecd24046", "features=0",
        "rumble main=0,0 triggers=32,16 sent=true", "outputs=1", "  id=0x11 n=78",
        "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89", "features=0",
      ]
    )
  }

  /// Arbitration encodes a 0 ms request, which Steam sends as a 65 ms pulse.
  @Test
  func steamArbitrationRumbleAtZeroMilliseconds() async throws {
    #expect(
      try await steamArbitrationRumbleSteps() == [
        "rumble ms=0 sent=true", "outputs=0", "features=2", "  id=0x00 n=64",
        "    8f0801e8fd00000100f000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8f0800e8fd00000100f700000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }
}
