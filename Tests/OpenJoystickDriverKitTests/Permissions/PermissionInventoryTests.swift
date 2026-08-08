import Foundation
import OpenJoystickDriverKit
import Testing

@Suite("Permission inventory") struct PermissionInventoryTests {
  @Test("Accessibility has the same app owner") func accessibilityHasOneAppOwner() {
    let accessibility = OJDPermissionRequirement.inventory.filter { $0.name == "Accessibility" }
    #expect(accessibility.count == 1)
    #expect(accessibility.first?.requested == true)
    #expect(accessibility.first?.owner == "OpenJoystickDriver app")
  }

  @Test("Input Monitoring has one app owner") func inputMonitoringHasOneAppOwner() {
    let owners = Set(
      OJDPermissionRequirement.inventory.filter { $0.name == "Input Monitoring" && $0.requested }
        .map(\.owner)
    )
    #expect(owners == ["OpenJoystickDriver app"])
  }

  @Test("Permission command does not reset TCC") func commandDoesNotResetTCC() throws {
    let root = try RepositoryRoot.from()
    let source = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Commands/PermissionsCommand.swift"
      ),
      encoding: .utf8
    )
    #expect(!source.contains("tccutil"))
    #expect(!source.contains("permissions refresh"))
  }
}
