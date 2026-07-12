import Foundation
import Testing

struct SettingsMutationParityTests {
  @Test
  func cliAndGuiExposeTheSameOutputAndResetMutations() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source("Sources/OpenJoystickDriver/CLI.swift", root: root)
    let userSpace = try source(
      "Sources/OpenJoystickDriver/Commands/UserSpaceCommand.swift",
      root: root
    )
    let output = try source(
      "Sources/OpenJoystickDriver/Commands/OutputModeCommand.swift",
      root: root
    )
    let reset = try source(
      "Sources/OpenJoystickDriver/Commands/ResetSettingsCommand.swift",
      root: root
    )
    let appModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel/XPCOperations.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/AdvancedCards.swift",
      root: root
    )
    let popover = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/MenuBarPopoverView.swift",
      root: root
    )

    #expect(cli.contains("case \"userspace\""))
    #expect(cli.contains("case \"output\""))
    #expect(cli.contains("case \"reset-settings\""))
    #expect(userSpace.contains("client.setUserSpaceVirtualDeviceEnabled"))
    #expect(output.contains("client.setOutputMode"))
    #expect(reset.contains("client.resetSettings"))

    #expect(appModel.contains("client.setUserSpaceVirtualDeviceEnabled"))
    #expect(appModel.contains("client.setOutputMode"))
    #expect(appModel.contains("client.resetSettings"))
    #expect(view.contains("model.setUserSpaceVirtualDeviceEnabled"))
    #expect(view.contains("model.setOutputMode"))
    #expect(view.contains("pendingConfirmation = .resetSettings"))
    #expect(popover.contains("case .resetSettings"))
    #expect(popover.contains("primaryButton: .destructive"))
  }

  @Test
  func guiExposesConfirmedDriverKitRemovalAndPermissionSettings() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cli = try source(
      "Sources/OpenJoystickDriver/Commands/SystemExtensionCommand.swift",
      root: root
    )
    let manager = try source(
      "Sources/OpenJoystickDriver/App/SystemExtensionManager.swift",
      root: root
    )
    let cards = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/SystemCards.swift",
      root: root
    )
    let popover = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/MenuBarPopoverView.swift",
      root: root
    )

    #expect(cli.contains("case \"uninstall\""))
    #expect(manager.contains("func uninstallExtension()"))
    #expect(cards.contains("pendingConfirmation = .systemExtensionUninstall"))
    #expect(popover.contains("case .systemExtensionUninstall"))
    #expect(popover.contains("model.extensionManager.uninstallExtension()"))
    #expect(cards.contains("model.openInputMonitoringSettings()"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
