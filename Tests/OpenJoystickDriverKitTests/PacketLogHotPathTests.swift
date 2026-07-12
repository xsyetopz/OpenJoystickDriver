import Foundation
import Testing

struct PacketLogHotPathTests {
  @Test
  func packetFormattingIsDeferredAndHiddenUiDoesNotFetch() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let pipeline = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriverKit/Device/DevicePipeline.swift"
      ),
      encoding: .utf8
    )
    let buffer = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriverKit/Diagnostics/PacketLogBuffer.swift"
      ),
      encoding: .utf8
    )
    let view = try String(
      contentsOf: rootURL.appendingPathComponent(
        "Sources/OpenJoystickDriver/Views/InputTestWindowView.swift"
      ),
      encoding: .utf8
    )

    #expect(!pipeline.contains("String(format: \"%02X\""))
    #expect(!pipeline.contains("var packetLog: [PacketLogEntry]"))
    #expect(pipeline.contains("snapshots.appendPacket(bytes: bytes, direction: direction)"))
    #expect(buffer.contains("func entries() -> [PacketLogEntry]"))
    #expect(!buffer.contains("removeFirst"))
    #expect(view.contains("startPacketLogRefreshTask()"))
    #expect(view.contains("packetLogTask?.cancel()"))
    #expect(view.contains("guard showPackets, let device = selectedDevice"))
  }
}
