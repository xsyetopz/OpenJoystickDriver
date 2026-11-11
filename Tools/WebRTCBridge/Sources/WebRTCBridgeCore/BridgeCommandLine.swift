/// The command line of `ojd-webrtc-bridge`: its usage text and how its arguments split.
public enum BridgeCommandLine {
  /// The text that `--help` prints, and that a bad command line prints to standard error.
  public static let usage = """
    usage: ojd-webrtc-bridge --role host|player [--signal offer|answer] [--socket PATH]
           [--token-name NAME] [--controller ID] [--persona Generic|SDLCompatible]
           [--ice-server URL]...
    Set OJD_TOKEN to the token that `ojd access grant --token NAME` printed.
    The offer and the answer are one line each: the bridge prints its own on stdout and reads the
    peer's from stdin. The player offers by default and the host answers.
    """

  /// The result of splitting the arguments.
  public enum Parsed: Equatable {
    /// `--help` is among the arguments: print `usage` to standard output and exit 0.
    case help
    /// Each `--name value` pair, grouped by name.
    case options([String: [String]])
    /// An argument is not an option or lacks its value: print `usage` to standard error and exit 1.
    case invalid
  }

  /// Splits the arguments into `--name value` pairs.
  ///
  /// `--help` anywhere in the arguments wins over every other argument.
  ///
  /// - Parameter arguments: The arguments without the program name.
  /// - Returns: `.help` when `--help` is present, `.invalid` for a bad argument, else the options.
  public static func parse(_ arguments: [String]) -> Parsed {
    if arguments.contains("--help") { return .help }
    var parsed: [String: [String]] = [:]
    var remaining = arguments[...]
    while let name = remaining.popFirst() {
      guard name.hasPrefix("--"), let value = remaining.popFirst() else { return .invalid }
      parsed[String(name.dropFirst(2)), default: []].append(value)
    }
    return .options(parsed)
  }
}
