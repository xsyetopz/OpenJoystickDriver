import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct TouchSurfaceCapabilityTests {
  @Test(arguments: [UInt16(0x05C4), UInt16(0x0CE6), UInt16(0x0DF2), UInt16(0x1102)])
  func advertisedSurfacesMatchDecodedFrames(_ productID: UInt16) throws {
    let steam = productID == 0x1102
    let identifier = DeviceIdentifier(vendorID: steam ? 0x28DE : 0x054C, productID: productID)
    let parser = ParserRegistry().parser(for: identifier)
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    if steam {
      report[2] = 1
      report[3] = 60
      report[10] = 0x18
    } else if productID == 0x05C4 {
      report[33] = 1
    }
    let events = try parser.parse(data: Data(report))
    let frames = events.compactMap { event -> ControllerTouchSample? in
      if case .touchSample(let frame) = event { return frame }
      return nil
    }
    let expected: [ControllerTouchSurface] = steam ? [.left, .right] : [.primary]
    #expect(frames.map(\.surface) == expected)
    #expect(parser.physicalInputCapabilities.touchSurfaces == expected)
    #expect(frames.allSatisfy {
      $0.contacts.count == Int(parser.physicalInputCapabilities.touchContactsPerFrame)
    })
    let data = try JSONEncoder().encode(parser.physicalInputCapabilities)
    #expect(try JSONDecoder().decode(PhysicalControllerInputCapabilities.self, from: data)
      == parser.physicalInputCapabilities)
  }

  @Test func unavailableTouchHasNoInventedSurface() {
    #expect(SwitchProParser().physicalInputCapabilities.touchSurfaces.isEmpty)
    #expect(PhysicalControllerInputCapabilities.none.touchSurfaces.isEmpty)
  }
}
