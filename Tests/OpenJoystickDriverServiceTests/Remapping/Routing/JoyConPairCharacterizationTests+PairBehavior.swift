import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

// Pinned Joy-Con pair transcripts; the rendering rules are on `JoyConPairCharacterizationTests`.
extension JoyConPairCharacterizationTests {
  /// The left half holds SL (bound to L), ZL, Minus, d-pad up and its stick while the right half
  /// taps buttons and moves its stick: no right-half step releases a left-half control.
  @Test
  func rightHalfNeverReleasesLeftHalf() async throws {
    let session = try await pairedSession()
    defer { session.harness.removeFiles() }
    let held: UInt32 = 0x20_0000 | 0x80_0000 | 0x100 | 0x2_0000
    let lines = try await session.run([
      Step(Self.left, held, stick: (4095, 2048)), Step(Self.right, 0x4), Step(Self.right, 0),
      Step(Self.right, 0x8 | 0x1), Step(Self.right, 0x1), Step(Self.right, 0),
      Step(Self.right, 0x40 | 0x80 | 0x200 | 0x1000), Step(Self.right, 0),
      Step(Self.right, 0, stick: (2048, 0)), Step(Self.right, 0), Step(Self.left, 0),
    ])
    #expect(
      lines == [
        "L a20100 4095,2048 [+Back +LeftTrigger +Auxiliary3 hat=North ls=32767,0]",
        "  pad L +Back", "  pad L +LeftTrigger", "  pad L +LeftShoulder", "  pad L d+DpadUp",
        "  pad L LeftStickX=32767", "R 4 2048,2048 [+South]", "  pad L +South",
        "R 0 2048,2048 [-South]", "  pad L -South", "R 9 2048,2048 [+East +West]", "  pad L +East",
        "  pad L +West", "R 1 2048,2048 [-East]", "  pad L -East", "R 0 2048,2048 [-West]",
        "  pad L -West", "R 12c0 2048,2048 [+RightShoulder +Start +Guide +RightTrigger]",
        "  pad L +RightShoulder", "  pad L +Start", "  pad L +Guide",
        "  pad L +RightTrigger",
        "R 0 2048,2048 [-RightShoulder -Start -Guide -RightTrigger]",
        "  pad L -RightShoulder", "  pad L -Start", "  pad L -Guide",
        "  pad L -RightTrigger", "R 0 2048,0 [rs=0,32767]", "  pad L RightStickY=32767",
        "R 0 2048,2048 [rs=0,0]", "  pad L RightStickY=0",
        "L 0 2048,2048 [-Back -LeftTrigger -Auxiliary3 hat=Neutral ls=0,0]", "  pad L -Back",
        "  pad L -LeftTrigger", "  pad L -LeftShoulder", "  pad L d-DpadUp",
        "  pad L LeftStickX=0",
      ]
    )
  }

  /// The reverse: the right half holds A, R, Plus and its stick while the left half taps.
  @Test
  func leftHalfNeverReleasesRightHalf() async throws {
    let session = try await pairedSession()
    defer { session.harness.removeFiles() }
    let held: UInt32 = 0x4 | 0x40 | 0x200
    let lines = try await session.run([
      Step(Self.right, held, stick: (0, 2048)), Step(Self.left, 0x20_0000), Step(Self.left, 0),
      Step(Self.left, 0x2_0000 | 0x100), Step(Self.left, 0x100), Step(Self.left, 0),
      Step(Self.left, 0x40_0000 | 0x2000 | 0x800), Step(Self.left, 0),
      Step(Self.left, 0, stick: (2048, 4095)), Step(Self.left, 0), Step(Self.right, 0),
    ])
    #expect(
      lines == [
        "R 244 0,2048 [+South +RightShoulder +Start rs=-32767,0]", "  pad L +South",
        "  pad L +RightShoulder", "  pad L +Start", "  pad L RightStickX=-32767",
        "L 200000 2048,2048 [+Auxiliary3]", "  pad L +LeftShoulder", "L 0 2048,2048 [-Auxiliary3]",
        "  pad L -LeftShoulder", "L 20100 2048,2048 [+Back hat=North]", "  pad L +Back",
        "  pad L d+DpadUp", "L 100 2048,2048 [hat=Neutral]", "  pad L d-DpadUp",
        "L 0 2048,2048 [-Back]",
        "  pad L -Back", "L 402800 2048,2048 [+LeftShoulder +LeftStickClick +Capture]",
        "  pad L +LeftShoulder", "  pad L +LeftStickClick", "  pad L +Capture",
        "L 0 2048,2048 [-LeftShoulder -LeftStickClick -Capture]", "  pad L -LeftShoulder",
        "  pad L -LeftStickClick", "  pad L -Capture", "L 0 2048,4095 [ls=0,-32767]",
        "  pad L LeftStickY=-32767", "L 0 2048,2048 [ls=0,0]", "  pad L LeftStickY=0",
        "R 0 2048,2048 [-South -RightShoulder -Start rs=0,0]", "  pad L -South",
        "  pad L -RightShoulder", "  pad L -Start", "  pad L RightStickX=0",
      ]
    )
  }

  /// Stopping the right half ends the pair: the shared device releases everything, including the
  /// left half's held controls, and the left half returns to virtual output.
  @Test
  func stoppingOneHalfReleasesPair() async throws {
    let session = try await pairedSession()
    defer { session.harness.removeFiles() }
    var lines = try await session.run([
      Step(Self.left, 0x20_0000 | 0x2_0000), Step(Self.right, 0x4),
    ])
    session.harness.recorder.removeAll()
    try await session.harness.router.stopController(Self.right)
    lines.append("stop R")
    lines += session.traces()
    lines += try await session.run([Step(Self.left, 0)])
    #expect(
      lines == [
        "L 220000 2048,2048 [+Auxiliary3 hat=North]", "  pad L +LeftShoulder", "  pad L d+DpadUp",
        "R 4 2048,2048 [+South]", "  pad L +South", "stop R", "  pad L -LeftShoulder",
        "  pad L -South d-DpadUp", "  virtual-stop L", "L 0 2048,2048 [-Auxiliary3 hat=Neutral]",
        "  virtual L [neutral]",
      ]
    )
  }

  /// Both halves drive one destination: right SL is bound to L while the left half holds L. The
  /// right half's tap and release leave the left half's L held.
  @Test
  func bothHalvesDriveOneDestination() async throws {
    let session = try await pairedSession(bindings: [
      RemappingBinding(source: .button(.auxiliary5), destination: .gamepadButton(.leftShoulder))
    ])
    defer { session.harness.removeFiles() }
    let lines = try await session.run([
      Step(Self.left, 0x40_0000), Step(Self.right, 0x20), Step(Self.right, 0),
      Step(Self.right, 0x20), Step(Self.left, 0), Step(Self.right, 0),
    ])
    #expect(
      lines == [
        "L 400000 2048,2048 [+LeftShoulder]", "  pad L +LeftShoulder",
        "R 20 2048,2048 [+Auxiliary5]", "R 0 2048,2048 [-Auxiliary5]",
        "R 20 2048,2048 [+Auxiliary5]",
        "L 0 2048,2048 [-LeftShoulder]", "R 0 2048,2048 [-Auxiliary5]", "  pad L -LeftShoulder",
      ]
    )
  }
}
