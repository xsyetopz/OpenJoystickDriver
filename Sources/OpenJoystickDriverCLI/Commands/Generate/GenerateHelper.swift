import Darwin
import Foundation
import JavaScriptCore

/// The helper process of `ojd generate`: evaluates one script in a bare JavaScript context.
///
/// The context has no file, network, or timer API.
package enum GenerateHelper {
  /// Runs the helper and exits the process when the environment asks for it; returns otherwise.
  ///
  /// The script path is the first argument after the executable name.
  package static func runAndExitIfRequested() {
    guard ProcessInfo.processInfo.environment[GenerateRunner.environmentKey] == "1" else { return }
    let path = CommandLine.arguments.dropFirst().first ?? ""
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { exit(2) }
    let context = JSContext()
    context?.evaluateScript(source)
    exit(0)
  }
}
