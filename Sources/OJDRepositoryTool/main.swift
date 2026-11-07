import Foundation
import OpenJoystickDriverKit

/// A call that the tool refuses.
///
/// It exits with ``exitCode``, which no check result uses, and names the call on standard error.
struct UsageError: Error {
  /// The exit status of a refused call.
  static let exitCode: Int32 = 64
  /// What is wrong with the call.
  let message: String
}

/// The usage text that the tool prints on standard error after a refused call.
private let usage = """
  usage:
    OJDRepositoryTool validate controllers <directory>
    OJDRepositoryTool validate descriptions <directory>
    OJDRepositoryTool validate profiles <path>...
    OJDRepositoryTool validate virtual-devices <path>...
    OJDRepositoryTool apply-patches --controllers <directory> --patches <directory>
      --out <directory>
    OJDRepositoryTool facts
    OJDRepositoryTool kebab <value>...
    OJDRepositoryTool mask-image <png> <frame> <keep>...
    OJDRepositoryTool format-json <file>...
  A path is a file, or a directory whose .json files are checked.
  validate controllers and descriptions read a directory at any depth. apply-patches reads
  Controller files at any depth and writes each to its relative path, and refuses a patch file
  that is not at the path its selector gives: a vendor directory for a vendorID with productID,
  the top of the directory for the others, so a deeper file is refused.
  facts prints one JSON object of the constants that Swift owns: apiVersion, schemaBase (the start
  of the $id of every schema), commandLineExitStatuses (the sorted exit statuses of ojd),
  domainCodePrefixes (the start of the codes of each error domain) and domainAreas (the en-US name
  of the area of each error domain). kebab prints one JSON object that maps
  each value to its CommandLineName.kebab spelling. Neither prints problems and both exit 0.
  mask-image rewrites a `screencapture -R <frame>` PNG so that every pixel outside all <keep>
  rectangles is transparent and every pixel inside one is unchanged. Each rectangle is
  x,y,width,height in global points, and each <keep> lies inside <frame>. The pixels per point
  are the image size over the frame size. It prints nothing and exits 0, or 64 for an image it
  cannot read or write.
  format-json rewrites each file in the record file text of OrderedJSON.formatted(), keeping the
  order of keys and the text of numbers. It prints nothing and exits 0, or 64 for a file that is
  not JSON or cannot be read or written.
  Each problem is one JSON line {"code", "file", "message"} on standard output. The exit status is
  0 without a problem, 1 with one, and 64 for a call that the tool refuses.
  """

/// The folder at `path`.
///
/// - Throws: ``UsageError`` when `path` is not a directory.
private func directory(_ path: String) throws -> URL {
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
    isDirectory.boolValue
  else { throw UsageError(message: "\(path) is not a directory") }
  return URL(fileURLWithPath: path, isDirectory: true)
}

/// The files that `paths` name, in the order given; a directory stands for its `.json` files in
/// file-name order.
///
/// - Throws: ``UsageError`` when no path is given or a path does not exist.
private func files(_ paths: [String]) throws -> [URL] {
  guard !paths.isEmpty else { throw UsageError(message: "no path given") }
  return try paths.flatMap { path -> [URL] in
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      throw UsageError(message: "\(path) does not exist")
    }
    guard isDirectory.boolValue else { return [URL(fileURLWithPath: path)] }
    return try FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: path, isDirectory: true),
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}

/// The values of the `names` options in `arguments`, which are option and value pairs.
///
/// - Throws: ``UsageError`` when an option is unknown, has no value, is given twice, or is missing.
private func options(_ arguments: [String], names: [String]) throws -> [String: String] {
  var values: [String: String] = [:]
  var index = 0
  while index < arguments.count {
    let name = arguments[index]
    guard names.contains(name) else { throw UsageError(message: "unknown option \(name)") }
    guard index + 1 < arguments.count else { throw UsageError(message: "\(name) needs a value") }
    guard values[name] == nil else { throw UsageError(message: "\(name) is given twice") }
    values[name] = arguments[index + 1]
    index += 2
  }
  for name in names where values[name] == nil {
    throw UsageError(message: "\(name) is required")
  }
  return values
}

/// Runs a `validate` or `apply-patches` subcommand and returns the problems it found.
///
/// - Throws: ``UsageError`` when the subcommand, its kind or its arguments are not valid.
private func run(_ arguments: [String]) throws -> [RepositoryProblem] {
  guard let command = arguments.first else { throw UsageError(message: "no subcommand given") }
  let rest = Array(arguments.dropFirst())
  switch command {
  case "validate":
    guard let kind = rest.first else { throw UsageError(message: "validate needs a kind") }
    let paths = Array(rest.dropFirst())
    switch kind {
    case "controllers", "descriptions":
      guard paths.count == 1, let path = paths.first else {
        throw UsageError(message: "validate \(kind) takes one directory")
      }
      let root = try directory(path)
      return kind == "controllers"
        ? RepositoryValidation.controllers(in: root) : RepositoryValidation.descriptions(in: root)
    case "profiles": return try files(paths).compactMap(RepositoryValidation.profile(at:))
    case "virtual-devices":
      return try files(paths).compactMap(RepositoryValidation.virtualDevice(at:))
    default: throw UsageError(message: "unknown validate kind \(kind)")
    }
  case "apply-patches":
    let values = try options(rest, names: ["--controllers", "--patches", "--out"])
    return RepositoryValidation.applyPatches(
      controllers: try directory(values["--controllers"] ?? ""),
      patches: try directory(values["--patches"] ?? ""),
      output: URL(fileURLWithPath: values["--out"] ?? "", isDirectory: true)
    )
  default: throw UsageError(message: "unknown subcommand \(command)")
  }
}

/// Rewrites each of `paths` as ``OrderedJSON/formatted()``.
///
/// - Throws: ``UsageError`` when no path is given or a file cannot be read, parsed or written.
private func formatJSON(_ paths: [String]) throws {
  guard !paths.isEmpty else { throw UsageError(message: "format-json needs a file") }
  for path in paths {
    let url = URL(fileURLWithPath: path)
    do {
      try OrderedJSON.parse(Data(contentsOf: url)).formattedData().write(to: url)
    } catch {
      throw UsageError(message: "\(path): \(error)")
    }
  }
}

/// The JSON line, ending in a newline, that reports `problem` on standard output.
private func line(_ problem: RepositoryProblem) throws -> Data {
  let object: [String: Any] = [
    "file": problem.file, "code": problem.code.rawValue, "message": problem.message,
  ]
  return try JSONSerialization.data(
    withJSONObject: object,
    options: [.sortedKeys, .withoutEscapingSlashes]
  ) + Data("\n".utf8)
}

/// The JSON object that the `facts` or `kebab` subcommand prints, or nil when `arguments` name a
/// check.
///
/// - Throws: ``UsageError`` when `facts` takes an argument or `kebab` has no value.
private func document(_ arguments: [String]) throws -> [String: Any]? {
  let rest = Array(arguments.dropFirst())
  switch arguments.first {
  case "facts":
    guard rest.isEmpty else { throw UsageError(message: "facts takes no argument") }
    let english = Localization(preferredLanguages: [Localization.sourceLocalization])
    return [
      "apiVersion": OpenJoystickDriverAPI.version,
      "schemaBase": OpenJoystickDriverAPI.schemaBase,
      "domainAreas": Dictionary(
        uniqueKeysWithValues: ErrorCode.Domain.allCases.map {
          ($0.rawValue, english.string($0.areaKey))
        }
      ),
      "commandLineExitStatuses": ErrorCode.commandLineExitStatuses.sorted(),
      "domainCodePrefixes": Dictionary(
        uniqueKeysWithValues: ErrorCode.Domain.allCases.map { ($0.rawValue, $0.codePrefix) }
      ),
    ]
  case "kebab":
    guard !rest.isEmpty else { throw UsageError(message: "kebab needs a value") }
    return Dictionary(rest.map { ($0, CommandLineName.kebab($0)) }) { first, _ in first }
  default: return nil
  }
}

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  if arguments.first == "mask-image" {
    try MaskImage.run(Array(arguments.dropFirst()))
    exit(0)
  }
  if arguments.first == "format-json" {
    try formatJSON(Array(arguments.dropFirst()))
    exit(0)
  }
  if let object = try document(arguments) {
    FileHandle.standardOutput.write(
      try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        + Data("\n".utf8)
    )
    exit(0)
  }
  let problems = try run(arguments)
  for problem in problems { FileHandle.standardOutput.write(try line(problem)) }
  exit(problems.isEmpty ? 0 : 1)
} catch let error as UsageError {
  FileHandle.standardError.write(Data("OJDRepositoryTool: \(error.message)\n\(usage)\n".utf8))
  exit(UsageError.exitCode)
}
