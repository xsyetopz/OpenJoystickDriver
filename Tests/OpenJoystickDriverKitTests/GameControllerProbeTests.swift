import Foundation
import Testing

struct GameControllerProbeTests {
  @Test
  func testProbeLogsGameControllerInputChanges() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let probeURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverGameControllerProbe/main.swift"
    )
    let source = try String(contentsOf: probeURL, encoding: .utf8)

    #expect(source.contains("installInputLogging(on:"))
    #expect(source.contains("valueChangedHandler"))
    #expect(source.contains("GC_INPUT"))
    #expect(source.contains("buttonA.isPressed"))
    #expect(source.contains("leftThumbstick.xAxis.value"))
  }

  @Test
  func testProbeCanInjectVirtualSelfTestDuringListenWindow() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let probeURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverGameControllerProbe/main.swift"
    )
    let packageURL = rootURL.appendingPathComponent("Package.swift")
    let source = try String(contentsOf: probeURL, encoding: .utf8)
    let package = try String(contentsOf: packageURL, encoding: .utf8)
    guard
      let probeTargetStart = package.range(of: "name: \"OpenJoystickDriverGameControllerProbe\""),
      let probeTargetEnd = package.range(
        of: ".testTarget(",
        range: probeTargetStart.upperBound..<package.endIndex
      )
    else {
      Issue.record("Could not locate GameController probe target in Package.swift")
      return
    }
    let probeTarget = String(package[probeTargetStart.lowerBound..<probeTargetEnd.lowerBound])

    #expect(!source.contains("import OpenJoystickDriverKit"))
    #expect(source.contains("let shouldInjectSelfTest = hasArg(\"--inject-selftest\")"))
    #expect(source.contains("Process()"))
    #expect(source.contains("--headless"))
    #expect(source.contains("selftest"))
    #expect(source.contains("$0.contains(\"User-space:\")"))
    #expect(source.contains("\"GC_SELFTEST \" + line"))
    #expect(probeTarget.contains("name: \"OpenJoystickDriverGameControllerProbe\""))
    #expect(!probeTarget.contains("dependencies: [\"OpenJoystickDriverKit\"]"))
  }
}
