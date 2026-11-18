import Foundation
import Testing

@testable import OpenJoystickDriverCLI

/// Every App Intent runs the code of an `ojd` command, so a Shortcuts action never does what the
/// command line cannot (`docs/development/scripting-surfaces.md`).
struct IntentCommandTests {
  /// The `ojd` command that holds the code of each App Intent.
  static let commands: [String: [String]] = [
    "GetControllersIntent": ["controller", "list"],
    "GetBatteryLevelIntent": ["controller", "show"],
    "AppVersionIntent": ["status"],
    "ActivateProfileIntent": ["profile", "activate"],
    "DeactivateProfileIntent": ["profile", "deactivate"],
    "SetProfileValueIntent": ["profile", "set"],
    "ListModsIntent": ["mod", "list"],
    "InstallModIntent": ["mod", "install"],
    "RemoveModIntent": ["mod", "remove"],
    "RumbleControllerIntent": ["controller", "rumble"],
    "SetPlayerIndicatorIntent": ["controller", "player"],
    "SetControllerLightIntent": ["controller", "light"],
  ]

  private static func declaredIntents() throws -> Set<String> {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Root
      .deletingLastPathComponent()  // OpenJoystickDriverCLITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/OpenJoystickDriver/platform/macos/Intents")
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
    let pattern = try Regex(#"struct\s+(\w+)\s*:\s*[^{]*\bAppIntent\b"#)
    var names: Set<String> = []
    for file in files {
      let text = try String(contentsOf: file, encoding: .utf8)
      for match in text.matches(of: pattern) {
        if let name = match.output[1].substring { names.insert(String(name)) }
      }
    }
    return names
  }

  @Test
  func everyIntentHasOJDCommand() throws {
    let declared = try Self.declaredIntents()
    #expect(!declared.isEmpty)
    let missing = declared.subtracting(Self.commands.keys).sorted()
    #expect(missing.isEmpty, "intents with no ojd command: \(missing)")
  }

  @Test
  func everyListedIntentExistsAndItsCommandReal() throws {
    let declared = try Self.declaredIntents()
    let paths = CLICommandTree.paths()
    for (intent, command) in Self.commands {
      #expect(declared.contains(intent), "no intent \(intent)")
      #expect(paths.contains(command), "\(intent) names no real command: \(command)")
    }
  }
}
