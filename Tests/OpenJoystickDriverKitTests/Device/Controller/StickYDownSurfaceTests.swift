import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Every surface a stick position crosses reads the stick pushed up as a negative Y.
struct StickYDownSurfaceTests {
  private static let up = ControllerState(leftStick: StickPosition(x: 0, y: -1))

  @Test
  func theWatchJSONCarriesANegativeYForAStickPushedUp() throws {
    let data = try JSONEncoder().encode(Self.up)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let stick = try #require(object["leftStick"] as? [String: Any])
    let y = try #require(stick["y"] as? Double)
    #expect(y < 0)
  }

  @Test
  func anEndpointFrameWithANegativeYReachesTheVirtualGamepadAsANegativeY() throws {
    let frame = try JSONDecoder().decode(
      VirtualFeedFrame.self,
      from: Data(#"{"axes":{"LeftStickY":-1}}"#.utf8)
    )
    #expect(frame.gamepadState.axes[.leftStickY] == -1)
  }

  @Test
  func theRemappingEngineSeesAStickPushedUpAsNegativeY() {
    let changes = RemappingEngineState.changes(from: .neutral, to: Self.up)
    #expect(changes == [.leftStick(x: 0, y: -1)])
  }

  @Test
  func virtualReportCarriesNegativeYAs() {
    let profile = VirtualHIDProfileID.generic.makeProfile()
    let report = profile.inputReport(for: Self.up)
    let y = Int16(bitPattern: UInt16(report[4]) | UInt16(report[5]) << 8)
    #expect(y < 0)
  }
}
