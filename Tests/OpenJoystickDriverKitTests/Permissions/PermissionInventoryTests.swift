import Foundation
import OpenJoystickDriverKit
import Testing

@Suite("Permission inventory")
struct PermissionInventoryTests {
  @Test("Accessibility is explicitly not requested")
  func accessibilityNotRequested() {
    let accessibility = OJDPermissionRequirement.inventory.filter {
      $0.name == "Accessibility"
    }
    #expect(accessibility.count == 1)
    #expect(accessibility.first?.requested == false)
  }

  @Test("Input Monitoring owners are explicit")
  func inputMonitoringOwners() {
    let owners = Set(
      OJDPermissionRequirement.inventory
        .filter { $0.name == "Input Monitoring" && $0.requested }
        .map(\.owner)
    )
    #expect(owners == ["OpenJoystickDriver app", "OpenJoystickDriver Daemon"])
  }

  @Test("Refresh is scoped and confirmed")
  func refreshSourceContract() throws {
    let root = try RepositoryRoot.from()
    let source = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Commands/PermissionsCommand.swift"
      ),
      encoding: .utf8
    )
    #expect(source.contains("arguments == [\"--confirm\"]"))
    #expect(source.contains("[\"reset\", \"ListenEvent\", identifier]"))
    #expect(!source.contains("[\"reset\", \"Accessibility\""))
  }
}
