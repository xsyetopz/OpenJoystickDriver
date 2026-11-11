import Darwin
import Foundation
import JavaScriptCore

/// The helper process of `ojd generate`: evaluates one script in a bare JavaScript context.
///
/// The context has no file, network, or timer API.
package enum GenerateHelper {
  /// Runs the helper and exits the process when the environment asks for it; returns otherwise.
  ///
  /// The script path is the first argument after the executable name. The helper writes one
  /// ``GenerateReport`` on standard output and exits 0, or exits 2 when it cannot read the script.
  package static func runAndExitIfRequested() {
    guard ProcessInfo.processInfo.environment[GenerateRunner.environmentKey] == "1" else { return }
    let path = CommandLine.arguments.dropFirst().first ?? ""
    guard let source = try? String(contentsOfFile: path, encoding: .utf8),
      let output = try? JSONEncoder().encode(report(of: source))
    else { exit(2) }
    FileHandle.standardOutput.write(output)
    exit(0)
  }

  /// Evaluates `source`, calls its `generate` function, and reports the result.
  private static func report(of source: String) -> GenerateReport {
    guard let context = JSContext() else {
      return .failure(message: "no JavaScript context", line: nil)
    }
    context.evaluateScript(source)
    if let failure = failure(of: context) { return failure }
    guard context.evaluateScript("typeof generate")?.toString() == "function" else {
      return .missingGenerate
    }
    let value = context.objectForKeyedSubscript("generate")?.call(withArguments: [])
    if let failure = failure(of: context) { return failure }
    let json = context.objectForKeyedSubscript("JSON")?
      .invokeMethod("stringify", withArguments: [value as Any])
    if let failure = failure(of: context) { return failure }
    return .result(json?.isUndefined == false ? json?.toString() : nil)
  }

  /// The failure that the last call left in `context`, or nil.
  private static func failure(of context: JSContext) -> GenerateReport? {
    guard let exception = context.exception else { return nil }
    let line = exception.objectForKeyedSubscript("line")
    return .failure(
      message: exception.toString() ?? "",
      line: line?.isNumber == true ? Int(line?.toInt32() ?? 0) : nil
    )
  }
}
