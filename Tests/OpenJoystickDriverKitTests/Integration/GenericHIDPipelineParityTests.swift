import Foundation
import Testing

struct GenericHIDPipelineParityTests {
  @Test
  func semanticHIDValuesReachOnlyOptInParsers() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let stream = try source(
      "Sources/OpenJoystickDriverKit/HID/DeviceStream.swift",
      root: root
    )
    let manager =
      try source(
        "Sources/OpenJoystickDriverKit/Device/DeviceManager/DeviceManager.swift",
        root: root
      )
      + source(
        "Sources/OpenJoystickDriverKit/Device/DeviceManager/HIDDetection.swift",
        root: root
      )
    let pipeline = try source(
      "Sources/OpenJoystickDriverKit/Device/DevicePipeline/DevicePipeline.swift",
      root: root
    )
    let parser = try source(
      "Sources/OpenJoystickDriverKit/Protocol/Parsers/GenericHIDParser.swift",
      root: root
    )
    let userSpaceOutput = try source(
      "Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Events.swift",
      root: root
    )
    let inputTest = try source(
      "Sources/OpenJoystickDriver/Views/InputTestWindowView/InputTestWindowView.swift",
      root: root
    )

    #expect(stream.contains("IOHIDManagerRegisterInputValueCallback"))
    #expect(stream.contains("IOHIDValueGetElement"))
    #expect(stream.contains("IOHIDElementGetUsagePage"))
    #expect(manager.contains("routeHIDElementValue"))
    #expect(pipeline.contains("parser as? any HIDElementValueParser"))
    #expect(parser.contains("HIDElementValueParser"))
    #expect(!parser.contains("Dropping input"))
    #expect(userSpaceOutput.contains("case .genericButton1: return 15"))
    #expect(inputTest.contains(".a, .b, .x, .y"))
    #expect(inputTest.contains(".genericButton1, .genericButton2"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
