#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverKit

  /// The Shortcuts action that returns the names of the installed mod packages, as
  /// `ojd mod list` lists them.
  @available(macOS 13, *)
  struct ListModsIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource("ui.shortcuts.action.listMods.title")
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource("ui.shortcuts.action.listMods.description")
    )

    /// Returns the name of each installed package.
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
      .result(value: ModPackageStore().entries().map(\.name))
    }
  }

  /// The Shortcuts action that installs a mod package folder, as `ojd mod install` does.
  @available(macOS 13, *)
  struct InstallModIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource("ui.shortcuts.action.installMod.title")
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource("ui.shortcuts.action.installMod.description")
    )

    /// The folder that holds `mod.plist`.
    @Parameter(title: LocalizedStringResource("ui.shortcuts.action.installMod.folder"))
    var folder: URL

    /// Whether to replace an installed package of the same name, as `--force` does.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.action.installMod.replace"),
      default: false
    )
    var replace: Bool

    /// Installs the package and returns its name.
    ///
    /// - Throws: ``CodedFailure`` with the E4xxx code that `ojd mod install` prints.
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
      let installed = try ModPackageStore().installPackage(from: folder, replace: replace)
      return .result(value: installed.manifest.name)
    }
  }

  /// The Shortcuts action that removes an installed mod package, as `ojd mod remove --force`
  /// does.
  @available(macOS 13, *)
  struct RemoveModIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource("ui.shortcuts.action.removeMod.title")
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource("ui.shortcuts.action.removeMod.description")
    )

    /// The name of the installed package.
    @Parameter(title: LocalizedStringResource("ui.shortcuts.action.removeMod.name"))
    var name: String

    /// Removes the package and returns its name.
    ///
    /// - Throws: ``CodedFailure`` with the E4xxx code that `ojd mod remove` prints.
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
      try ModPackageStore().removePackage(named: name)
      return .result(value: name)
    }
  }
#endif
