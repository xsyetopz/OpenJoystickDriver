import Testing

@testable import OpenJoystickDriver

struct CommandCatalogTests {
  @Test func catalogPathsAreUniqueAndRenderedOnce() {
    let commands = InstalledCommandCatalog.commands
    let paths = commands.map(\.path)
    let help = InstalledCLIHelpRenderer.render(commands: commands)

    #expect(Set(paths).count == paths.count)
    for path in paths {
      #expect(help.components(separatedBy: "  \(path)\n").count == 2)
    }
  }

  @Test func catalogUsesStableLogicalOrder() {
    let groups = InstalledCommandCatalog.commands.map(\.group)
    let order = ["Overview", "Controllers", "Configuration", "System", "Support"]

    #expect(groups == groups.sorted { left, right in
      guard let leftIndex = order.firstIndex(of: left),
        let rightIndex = order.firstIndex(of: right)
      else {
        return false
      }
      return leftIndex < rightIndex
    })
    #expect(InstalledCommandCatalog.commands.first?.path == "status [--json]")
  }

  @Test func catalogSummariesAreConciseAndActionOriented() {
    let actionVerbs = ["Show", "List", "Watch", "Test", "Manage", "Review", "Run", "Check"]

    for command in InstalledCommandCatalog.commands {
      #expect(!command.summary.isEmpty)
      #expect(command.summary.count <= 60)
      #expect(actionVerbs.contains { command.summary.hasPrefix($0) })
    }
  }

  @Test func rootHelpRetainsEveryPublicFamilyAndPlainOutputGuidance() {
    let help = CLIHelp.text

    let families = [
      "status", "controller", "map", "app", "extension", "permissions", "compat", "test",
      "diagnose", "update",
    ]
    for family in families {
      #expect(help.contains(family))
    }
    #expect(help.contains("Output never relies on color alone."))
    #expect(help.contains("--timeout <seconds>"))
    #expect(help.contains("compat set <identity>"))
  }
}
