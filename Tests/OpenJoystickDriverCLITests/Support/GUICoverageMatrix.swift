/// The CLI-to-GUI coverage matrix of `design.md` D10, held as data.
///
/// It lives with the tests because only the coverage tests read it; the GUI does not consume it.
///
/// D10 states the area matrix per command group, so a `GUIPlace` covers every command whose path
/// starts with its `prefix`. Every command maps to a place. `GUICoverageEntries` names, per leaf
/// and behavior-changing option, the GUI symbol that performs it, and lists what only a terminal
/// can do.
struct GUIPlace: Equatable {
  /// The command path the entry covers, such as `["config", "show"]`.
  let prefix: [String]
  /// The GUI area of D10 that holds the command.
  let area: String
  /// The main menu entry of D10, or nil where D10 says none.
  let mainMenu: String?
  /// The status item entry of D10, or nil where D10 says none.
  let statusItem: String?
}

/// The GUI place of one `--json` field, for a field a command prints that the GUI shows as a named
/// element.
///
/// The command-group table above says where a command lives; this one says where a field of its
/// output shows.
struct GUIField: Equatable {
  /// The command path, such as `["controller", "show"]`.
  let command: [String]
  /// The dotted `--json` field, such as `serving.route`.
  let field: String
  /// The element of the GUI area that shows the field.
  let place: String
}

enum GUICoverageMatrix {
  /// Fields the GUI shows by name: the serving route and persona of
  /// `ojd controller show`.
  static let fields: [GUIField] = [
    GUIField(
      command: ["controller", "show"],
      field: "serving.route",
      place: "Controllers > controller detail > Serving route fact"
    ),
    GUIField(
      command: ["controller", "show"],
      field: "serving.persona",
      place: "Controllers > controller detail > Published as fact"
    ),
  ]

  /// D10 rows, one entry per CLI group named in the row.
  static let places: [GUIPlace] =
    row(
      [["status"], ["transport-extension"], ["permission"], ["service"]],
      area: "problem banner, Controllers, Access",
      mainMenu: nil,
      statusItem: "status line, Open Window"
    )
    + row(
      [["controller"], ["virtual"], ["config", "show"], ["config", "set"], ["config", "unset"]],
      area: "Controllers",
      mainMenu: "Controller menu",
      statusItem: "Controllers submenu"
    )
    + row(
      [["profile"], ["binding"], ["macro"]],
      area: "Profiles",
      mainMenu: "Profile menu, File > Import/Export Profile",
      statusItem: "Profiles submenu"
    )
    + row(
      [["record"], ["mod"]],
      area: "Library",
      mainMenu: "File > Install Record or Mod",
      statusItem: nil
    )
    + row([["generate"]], area: "Library", mainMenu: nil, statusItem: nil)
    + row([["access"]], area: "Access", mainMenu: nil, statusItem: "Grant Access")
    + row(
      [["log"], ["diagnose"], ["explain"]],
      area: "Activity",
      mainMenu: "File > Save Support Report, Save Activity Log; Help",
      statusItem: "Help submenu"
    )
    + row(
      [["setting"], ["update"], ["migrate"]],
      area: "Settings window",
      mainMenu: "App > Settings",
      statusItem: "Settings"
    )

  private static func row(
    _ groups: [[String]],
    area: String,
    mainMenu: String?,
    statusItem: String?
  ) -> [GUIPlace] {
    groups.map { GUIPlace(prefix: $0, area: area, mainMenu: mainMenu, statusItem: statusItem) }
  }

  /// The entry that covers `path`, the longest matching prefix.
  static func place(for path: [String], in places: [GUIPlace] = places) -> GUIPlace? {
    places.filter { path.starts(with: $0.prefix) }.max { $0.prefix.count < $1.prefix.count }
  }

  /// The commands that run something (leaves) and have no GUI place.
  static func unmapped(in paths: [[String]], places: [GUIPlace] = places) -> [[String]] {
    let leaves = paths.filter { path in
      !paths.contains { $0.count > path.count && $0.starts(with: path) }
    }
    return leaves.filter { place(for: $0, in: places) == nil }
  }

  /// Entries that match no command, so a rename or removal cannot leave a stale row.
  static func stale(in paths: [[String]], places: [GUIPlace] = places) -> [GUIPlace] {
    places.filter { entry in !paths.contains { $0.starts(with: entry.prefix) } }
  }
}
