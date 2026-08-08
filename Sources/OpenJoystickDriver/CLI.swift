import Foundation
import OpenJoystickDriverKit

struct CLI {
  func run(arguments: ArraySlice<String>) {
    installCLIShutdownHandlers()
    do { try CLIGrammar(arguments: Array(arguments)).run() } catch let error as CLIParseError {
      fputs("error: \(error.localizedDescription)\n", stderr)
      fputs("\n\(CLIHelp.text)\n", stderr)
      exit(CLIParseError.exitCode)
    } catch {
      fputs("error: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}
