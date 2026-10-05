import ArgumentParser

/// Finds the subcommand a mistyped command name most likely meant. It only suggests; a
/// suggestion never runs.
enum CommandSuggestion {
  struct Match: Equatable {
    /// The word the user typed.
    let typed: String
    /// The full command line of the nearest subcommand, such as `ojd controller list`, or nil
    /// when no subcommand is near.
    let suggestion: String?
  }

  /// Global options that take a separate value; their value is not a command name.
  private static let valueOptions: Set<String> = ["--timeout"]

  /// Walks the command words in `arguments` and returns the first word that names no
  /// subcommand, with its nearest subcommand. Returns nil once a command without subcommands
  /// is reached, because its words are arguments, not command names.
  static func match(
    arguments: [String],
    root: any ParsableCommand.Type = OJDCommand.self
  ) -> Match? {
    var command = root
    var path = [root._commandName]
    var index = arguments.startIndex
    while index < arguments.endIndex {
      let argument = arguments[index]
      index += 1
      if argument == "--" { return nil }
      if argument.hasPrefix("-") {
        if valueOptions.contains(argument) { index += 1 }
        continue
      }
      let subcommands = command.configuration.subcommands
      guard !subcommands.isEmpty, argument != "help" else { return nil }
      if let next = subcommands.first(where: { $0._commandName == argument }) {
        command = next
        path.append(next._commandName)
        continue
      }
      let nearest = nearest(to: argument, in: subcommands.map { $0._commandName })
      return Match(
        typed: argument,
        suggestion: nearest.map { (path + [$0]).joined(separator: " ") }
      )
    }
    return nil
  }

  /// The closest name within a small edit distance; the first declared name wins a tie.
  static func nearest(to typed: String, in names: [String]) -> String? {
    let limit = typed.count <= 4 ? 1 : 2
    var best: (name: String, distance: Int)?
    for name in names {
      let distance = editDistance(typed.lowercased(), name)
      if distance <= limit, distance < (best?.distance ?? .max) { best = (name, distance) }
    }
    return best?.name
  }

  /// Optimal string alignment distance: insertions, deletions, substitutions, and swaps of
  /// adjacent characters each cost one.
  static func editDistance(_ lhs: String, _ rhs: String) -> Int {
    let lhs = Array(lhs)
    let rhs = Array(rhs)
    if lhs.isEmpty { return rhs.count }
    if rhs.isEmpty { return lhs.count }
    var table = Array(repeating: Array(repeating: 0, count: rhs.count + 1), count: lhs.count + 1)
    for row in 0...lhs.count { table[row][0] = row }
    for column in 0...rhs.count { table[0][column] = column }
    for row in 1...lhs.count {
      for column in 1...rhs.count {
        let cost = lhs[row - 1] == rhs[column - 1] ? 0 : 1
        var value = min(
          table[row - 1][column] + 1,
          table[row][column - 1] + 1,
          table[row - 1][column - 1] + cost
        )
        if row > 1, column > 1, lhs[row - 1] == rhs[column - 2], lhs[row - 2] == rhs[column - 1] {
          value = min(value, table[row - 2][column - 2] + 1)
        }
        table[row][column] = value
      }
    }
    return table[lhs.count][rhs.count]
  }
}
