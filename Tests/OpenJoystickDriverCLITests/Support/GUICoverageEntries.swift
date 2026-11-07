import ArgumentParser
import Foundation

@testable import OpenJoystickDriverCLI

/// One CLI leaf (`option == nil`) or one behavior-changing option of a leaf, with its GUI place.
struct GUICoverageEntry: Equatable {
  /// The command path, such as `["controller", "rumble"]`.
  let command: [String]
  /// The long option, such as `--duration`; nil for the leaf itself.
  let option: String?
  /// A declaration in the GUI sources that performs the item. `GUISources` checks that it is
  /// declared and used outside its declaration.
  let symbol: String

  var key: String {
    ([command.joined(separator: " ")] + (option.map { [$0] } ?? [])).joined(separator: " ")
  }
}

/// A leaf or option that a window cannot naturally perform (D10).
struct CLIOnlyItem: Equatable {
  /// The command path.
  ///
  /// For an option, nil means every command that has it.
  let command: [String]?
  let option: String?
  let reason: String
}

/// The per-leaf and per-option coverage of the real command tree.
///
/// D10 says what a window cannot naturally do; everything else names the GUI symbol that does it.
enum GUICoverageEntries {
  static let entries: [GUICoverageEntry] =
    status + controller + profile + binding + virtual + record + mod + access + system

  /// Leaves and options only a terminal or script performs.
  ///
  /// The D10 text names each of them, and `GUICoverageTests` checks that.
  static let cliOnly: [CLIOnlyItem] =
    [
      CLIOnlyItem(
        command: ["virtual", "feed"],
        option: nil,
        reason: "reads controller frames from standard input"
      ),
      CLIOnlyItem(
        command: ["service", "start"],
        option: nil,
        reason: "the app process hosts the service, so a window cannot start it"
      ),
      CLIOnlyItem(
        command: ["service", "stop"],
        option: nil,
        reason: "the app process hosts the service, so a window cannot stop it"
      ),
      CLIOnlyItem(
        command: ["service", "wait"],
        option: nil,
        reason: "a window exists only once the service listens, so nothing waits"
      ),
      CLIOnlyItem(
        command: ["help"],
        option: nil,
        reason: "terminal help"
      ),
    ]
    + ["--all", "--first-press", "--duration", "--output"].map {
      CLIOnlyItem(
        command: ["controller", "watch"],
        option: $0,
        reason: "scripting option of a stream a window shows continuously"
      )
    }
    + ["--json", "--plain", "--quiet", "--no-color", "--no-input"].map {
      CLIOnlyItem(command: nil, option: $0, reason: "output-only option")
    }
    + [
      CLIOnlyItem(
        command: nil,
        option: "--timeout",
        reason:
          "bounds how long a terminal command waits for the service; a window has no such wait"
      )
    ]
    + ["--force", "--dry-run"].map {
      CLIOnlyItem(
        command: nil,
        option: $0,
        reason: "a window confirms in a sheet and shows the result, so it needs neither"
      )
    }
    + ["--help", "--version"].map {
      CLIOnlyItem(command: nil, option: $0, reason: "terminal help and version")
    }
    + [
      CLIOnlyItem(
        command: ["diagnose"],
        option: "--frames",
        reason: "the window of a frame-timing run started in a terminal while the sticks move"
      )
    ]

  // MARK: Entries

  private static let status = [
    leaf("status", "MainWindowProblemBanner"),
    leaf("permission list", "AccessPermissionRow"),
    leaf("permission request", "requestPermission"),
    leaf("transport-extension status", "refreshSystemExtensionSetup"),
    leaf("transport-extension activate", "startSystemExtensionSetup"),
    leaf("transport-extension deactivate", "uninstallSystemExtension"),
  ]

  private static let controller = [
    leaf("controller list", "ControllersView"),
    leaf("controller show", "ControllerDetailFacts"),
    leaf("controller watch", "InputTestLiveInputView"),
    leaf("controller capture", "ControllerPacketCapture"),
    option("controller capture", "--duration", "ControllerTimedActionSheet"),
    leaf("controller rumble", "rumbleCommand"),
    option("controller rumble", "--left", "InputTestRumbleMotorControl"),
    option("controller rumble", "--right", "InputTestRumbleMotorControl"),
    option("controller rumble", "--left-trigger", "InputTestRumbleMotorControl"),
    option("controller rumble", "--right-trigger", "InputTestRumbleMotorControl"),
    option("controller rumble", "--duration", "clampedRumbleDuration"),
    leaf("controller light", "applyColor"),
    option("controller light", "--color", "applyColor"),
    option("controller light", "--brightness", "applyBrightness"),
    leaf("controller player", "applyPlayerIndicator"),
    leaf("controller suspend", "suspendController"),
    leaf("controller resume", "resumeController"),
    leaf("controller disconnect", "disconnectWirelessController"),
    leaf("controller calibrate", "MotionCalibrationControls"),
    leaf("controller pair", "pairRemappingJoyCons"),
    option("controller pair", "--profile", "ProfileJoyConPairSheet"),
    leaf("controller unpair", "unpairRemappingJoyCons"),
    leaf("controller claim", "setControllerServer"),
    leaf("controller release", "setControllerServer"),
    leaf("config show", "ControllerTuningRows"),
    option("config show", "--controller", "ControllerTuningRows"),
    leaf("config set", "setControllerTuning"),
    option("config set", "--controller", "setControllerTuning"),
    leaf("config unset", "setControllerTuning"),
    option("config unset", "--controller", "setControllerTuning"),
  ]

  private static let profile = [
    leaf("profile list", "ProfilesView"),
    leaf("profile show", "ProfileEditorView"),
    leaf("profile create", "beginCreatingProfile"),
    option("profile create", "--controller", "ProfileControllerChoice"),
    option("profile create", "--app", "ProfileCreationFields"),
    option("profile create", "--virtual-gamepad", "ProfileOutputPolicyView"),
    option("profile create", "--physical-input", "ProfileOutputPolicyView"),
    leaf("profile duplicate", "ProfileDuplicateSheet"),
    leaf("profile rename", "updateMetadata"),
    leaf("profile delete", "deleteProfile"),
    leaf("profile activate", "activateProfile"),
    option("profile activate", "--allow-empty", "requestActivation"),
    leaf("profile deactivate", "deactivateProfile"),
    leaf("profile import", "chooseProfileToImport"),
    leaf("profile validate", "validateProfileFile"),
    leaf("profile export", "exportProfile"),
    option("profile export", "--output", "exportProfile"),
    leaf("profile get", "ProfileEditorView"),
    leaf("profile set", "updateMetadata"),
    leaf("profile edit", "ProfileEditorView"),
    leaf("profile recover", "recoverProfileIssue"),
  ]

  private static let binding = [
    leaf("binding list", "ProfileEditorView"),
    leaf("binding set", "addBinding"),
    option("binding set", "--behavior", "BindingBehaviorSheet"),
    option("binding set", "--pulse-ms", "pulseDurationMs"),
    option("binding set", "--deadzone", "AxisAdjustmentSheet"),
    option("binding set", "--gain", "AxisAdjustmentSheet"),
    option("binding set", "--invert", "AxisAdjustmentSheet"),
    option("binding set", "--response-curve", "AxisAdjustmentSheet"),
    option("binding set", "--digital-threshold", "AxisAdjustmentSheet"),
    option("binding set", "--turbo-rate", "turboRate"),
    option("binding set", "--turbo-duty", "turboDuty"),
    option("binding set", "--long-hold", "longHoldDuration"),
    option("binding set", "--double-tap", "doubleTapWindow"),
    option("binding set", "--actions-json", "ProfileAdditionalActionsView"),
    leaf("binding clear", "removeBinding"),
    option("binding clear", "--all", "removeAllAssignments"),
  ]

  private static let virtual = [
    leaf("virtual show", "VirtualHIDProfileOverrideView"),
    leaf("virtual set", "setVirtualHIDProfileOverride"),
    option("virtual set", "--unit", "VirtualHIDProfileScopeChoice"),
    leaf("virtual reset", "resetVirtualHIDProfileOverride"),
    option("virtual reset", "--all", "resetAllVirtualHIDProfileOverrides"),
    option("virtual reset", "--unit", "VirtualHIDProfileScopeChoice"),
    leaf("virtual export-mapping", "exportMapping"),
    option("virtual export-mapping", "--format", "ExportMappingAccessory"),
    leaf("virtual launch", "VirtualGamepadLaunch"),
    option("virtual launch", "--sdl-gamecontroller-backend", "chooseProgram"),
  ]

  private static let record = [
    leaf("record draft", "ControllerRecordDrafting"),
    option("record draft", "--duration", "ControllerTimedActionSheet"),
    option("record draft", "--from-sdl", "draftFromSDL"),
    leaf("record list", "LibraryListView"),
    option("record list", "--bundled", "LibraryScope"),
    leaf("record show", "LibraryRecordDetail"),
    leaf("record validate", "validateLibraryItem"),
    leaf("record install", "beginInstallRecord"),
    leaf("record remove", "removeRecord"),
    leaf("record test", "testSelectedRecord"),
    option("record test", "--packets", "chooseCapture"),
    option("record test", "--expect", "chooseExpectation"),
  ]

  private static let mod = [
    leaf("mod validate", "checkMod"),
    leaf("mod install", "beginInstallMod"),
    leaf("mod list", "LibraryModItem"),
    leaf("mod remove", "removeMod"),
  ]

  private static let access = [
    leaf("access status", "AccessAreaView"),
    leaf("access enable", "requestEnableEndpoint"),
    leaf("access disable", "disableEndpoint"),
    leaf("access list", "grantsSection"),
    leaf("access grant", "requestGrant"),
    option("access grant", "--token", "requestGrantToken"),
    option("access grant", "--origin", "AccessTokenDraft"),
    option("access grant", "--scope", "scopeChoices"),
    leaf("access revoke", "requestRevoke"),
    option("access revoke", "--scope", "partialRevoke"),
    leaf("access web enable", "requestEnableWeb"),
    option("access web enable", "--port", "webPort"),
    option("access web enable", "--automatic", "chooseAutomaticPort"),
    leaf("access web disable", "disableWeb"),
  ]

  private static let system = [
    leaf("setting list", "SettingsPreferencesModel"),
    leaf("setting get", "SettingsPreferencesModel"),
    leaf("setting set", "SettingsPreferencesModel"),
    leaf("setting reset", "resetSettings"),
    leaf("setting test-notification", "sendTestNotification"),
    leaf("log show", "ActivityLogView"),
    option("log show", "--follow", "setFollowing"),
    option("log show", "--lines", "setLineCount"),
    leaf("log path", "showInFinder"),
    leaf("log export", "saveActivityLog"),
    option("log export", "--lines", "setLineCount"),
    leaf("diagnose", "ActivityDiagnosticsModel"),
    option("diagnose", "--output", "saveSupportReport"),
    option("diagnose", "--soak", "SoakTestSheet"),
    option("diagnose", "--interval-ms", "SoakTestSheet"),
    option("diagnose", "--rss-limit-mib", "SoakTestSheet"),
    option("diagnose", "--footprint-limit-mib", "SoakTestSheet"),
    leaf("update check", "checkForUpdates"),
    option("update check", "--prerelease", "setIncludePrereleaseUpdates"),
    leaf("explain", "ErrorCodeExplainerView"),
  ]

  // MARK: Builders

  private static func leaf(_ path: String, _ symbol: String) -> GUICoverageEntry {
    GUICoverageEntry(
      command: path.split(separator: " ").map(String.init),
      option: nil,
      symbol: symbol
    )
  }

  private static func option(
    _ path: String,
    _ option: String,
    _ symbol: String
  )
    -> GUICoverageEntry
  {
    GUICoverageEntry(
      command: path.split(separator: " ").map(String.init),
      option: option,
      symbol: symbol
    )
  }
}

/// The GUI sources, scanned for the declarations the entries name.
enum GUISources {
  /// The repository root, from this file's place under `Tests/<target>/Support`.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  static let directories = ["Sources/OpenJoystickDriverPresentation", "Sources/OpenJoystickDriver"]

  struct ReadError: Error, CustomStringConvertible {
    let description: String
  }

  /// Every GUI Swift file's code, joined, with comments and string literals removed.
  ///
  /// A missing directory or an unreadable file stops the test run.
  static let text: String = {
    do {
      return try readCode()
    } catch {
      fatalError("GUI sources unreadable: \(error)")
    }
  }()

  static func readCode() throws -> String {
    var parts: [String] = []
    for directory in directories {
      let url = root.appendingPathComponent(directory)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { throw ReadError(description: "missing directory \(url.path)") }
      var failure: Error?
      guard
        let files = FileManager.default.enumerator(
          at: url,
          includingPropertiesForKeys: nil,
          errorHandler: { _, error in
            failure = error
            return false
          }
        )
      else { throw ReadError(description: "cannot enumerate \(url.path)") }
      var found = 0
      for case let file as URL in files where file.pathExtension == "swift" {
        parts.append(strippingCommentsAndStrings(try String(contentsOf: file, encoding: .utf8)))
        found += 1
      }
      if let failure { throw failure }
      if found == 0 { throw ReadError(description: "no Swift files in \(url.path)") }
    }
    return parts.joined(separator: "\n")
  }

  /// Whether `symbol` is declared in the GUI sources and used outside its declarations.
  static func isDeclaredAndReferenced(_ symbol: String) -> Bool {
    let name = NSRegularExpression.escapedPattern(for: symbol)
    let declaration =
      "\\b(func|case|var|let|struct|class|enum|actor|protocol|typealias)\\s+\(name)\\b"
    let declarations = count(of: declaration)
    return declarations >= 1 && count(of: "\\b\(name)\\b") > declarations
  }

  private static func count(of pattern: String) -> Int {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      fatalError("invalid pattern \(pattern)")
    }
    return expression.numberOfMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text)
    )
  }

  /// Swift source without line comments, nested block comments or string literal text.
  ///
  /// The code inside string interpolations stays, because it runs.
  static func strippingCommentsAndStrings(_ source: String) -> String {
    let chars = Array(source)
    var output = ""
    var index = 0
    // One open string literal: its closing quote count and `#` count, and the paren depth of an
    // open interpolation (0 while in text).
    struct Literal {
      let quotes: Int
      let hashes: Int
      var depth = 0
    }
    var literals: [Literal] = []

    func matches(_ text: String, at position: Int) -> Bool {
      let target = Array(text)
      return position + target.count <= chars.count
        && Array(chars[position..<position + target.count]) == target
    }

    while index < chars.count {
      if var literal = literals.last, literal.depth == 0 {
        let hashes = String(repeating: "#", count: literal.hashes)
        let close = String(repeating: "\"", count: literal.quotes) + hashes
        if matches(close, at: index) {
          literals.removeLast()
          index += close.count
        } else if matches("\\" + hashes + "(", at: index) {
          literal.depth = 1
          literals[literals.count - 1] = literal
          index += 2 + literal.hashes
        } else if chars[index] == "\\", literal.hashes == 0 {
          index += 2
        } else {
          index += 1
        }
        continue
      }
      if matches("//", at: index) {
        while index < chars.count, chars[index] != "\n" { index += 1 }
      } else if matches("/*", at: index) {
        var depth = 0
        repeat {
          if matches("/*", at: index) {
            depth += 1
            index += 2
          } else if matches("*/", at: index) {
            depth -= 1
            index += 2
          } else {
            index += 1
          }
        } while depth > 0 && index < chars.count
      } else if chars[index] == "#" || chars[index] == "\"" {
        var hashes = 0
        var position = index
        while position < chars.count, chars[position] == "#" {
          hashes += 1
          position += 1
        }
        guard position < chars.count, chars[position] == "\"" else {
          output.append(chars[index])
          index += 1
          continue
        }
        let quotes = matches("\"\"\"", at: position) ? 3 : 1
        literals.append(Literal(quotes: quotes, hashes: hashes))
        index = position + quotes
      } else {
        if var literal = literals.last {
          if chars[index] == "(" { literal.depth += 1 }
          if chars[index] == ")" { literal.depth -= 1 }
          literals[literals.count - 1] = literal
          if literal.depth == 0 {
            index += 1
            continue
          }
        }
        output.append(chars[index])
        index += 1
      }
    }
    return output
  }
}

/// The CLI surface read from the real command tree: leaves and their options and flags, hidden ones
/// included, named by the long name or, where there is none, the short one.
///
/// Positional operands are excluded.
struct CLISurfaceItem: Hashable {
  let command: [String]
  let option: String?

  var key: String {
    ([command.joined(separator: " ")] + (option.map { [$0] } ?? [])).joined(separator: " ")
  }
}

enum SurfaceError: Error, CustomStringConvertible {
  case noRoot
  case unnamedCommand(path: [String])
  case unnamedOption(command: [String])

  var description: String {
    switch self {
    case .noRoot: "the help dump has no root command"
    case .unnamedCommand(let path): "a subcommand of \(path) has no name"
    case .unnamedOption(let command): "an option of \(command) has neither a long nor a short name"
    }
  }
}

enum CLISurface {
  static func items() throws -> [CLISurfaceItem] {
    let data = Data(OJDCommand._dumpHelp().utf8)
    let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let root = document?["command"] as? [String: Any] else { throw SurfaceError.noRoot }
    var items: [CLISurfaceItem] = []
    try collect(root, path: [], into: &items)
    return items
  }

  private static func collect(
    _ command: [String: Any],
    path: [String],
    into items: inout [CLISurfaceItem]
  ) throws {
    let subcommands = command["subcommands"] as? [[String: Any]] ?? []
    if subcommands.isEmpty { items.append(CLISurfaceItem(command: path, option: nil)) }
    for argument in command["arguments"] as? [[String: Any]] ?? [] {
      if argument["kind"] as? String == "positional" { continue }
      let names = argument["names"] as? [[String: Any]] ?? []
      func name(_ kind: String) -> String? {
        names.first { $0["kind"] as? String == kind }?["name"] as? String
      }
      if let long = name("long") {
        items.append(CLISurfaceItem(command: path, option: "--\(long)"))
      } else if let short = name("short") {
        items.append(CLISurfaceItem(command: path, option: "-\(short)"))
      } else {
        throw SurfaceError.unnamedOption(command: path)
      }
    }
    for subcommand in subcommands {
      guard let name = subcommand["commandName"] as? String else {
        throw SurfaceError.unnamedCommand(path: path)
      }
      try collect(subcommand, path: path + [name], into: &items)
    }
  }
}
