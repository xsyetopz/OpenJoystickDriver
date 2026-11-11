public import Foundation

/// Finds the file that runs for a program name and builds the process that runs it.
///
/// The command line and the app both launch a game this way.
public enum ProgramExecutable {
  /// Why a program name has no executable file.
  public enum Failure: Error, Equatable, Sendable {
    /// The `.app` bundle has no main executable.
    case noExecutable
    /// The path is not an executable file.
    case notExecutable
    /// No directory of the search path holds an executable of that name.
    case notFound
  }

  /// The file that runs for `name`: the main executable of an `.app` bundle, a path as given, or
  /// the first match in `searchPath`, a `PATH` value.
  public static func url(for name: String, searchPath: String?) throws -> URL {
    let fileManager = FileManager.default
    if name.hasSuffix(".app") || name.hasSuffix(".app/") {
      guard let url = Bundle(url: URL(fileURLWithPath: name))?.executableURL else {
        throw Failure.noExecutable
      }
      return url
    }
    if name.contains("/") {
      guard fileManager.isExecutableFile(atPath: name) else { throw Failure.notExecutable }
      return URL(fileURLWithPath: name)
    }
    let directories = (searchPath ?? "").split(separator: ":").map(String.init)
    for directory in directories {
      let path = directory + "/" + name
      var isDirectory: ObjCBool = false
      if fileManager.isExecutableFile(atPath: path),
        unsafe fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      {
        return URL(fileURLWithPath: path)
      }
    }
    throw Failure.notFound
  }

  /// A process that runs `executable` with `environment`.
  ///
  /// Its output goes to `standardOutput` when given, else to the standard output of this process.
  public static func process(
    executable: URL,
    arguments: [String],
    environment: [String: String],
    standardOutput: FileHandle?
  ) -> Process {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    if let standardOutput { process.standardOutput = standardOutput }
    return process
  }
}
