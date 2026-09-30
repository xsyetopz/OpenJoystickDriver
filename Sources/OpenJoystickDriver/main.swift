import Dispatch
import Foundation
import OpenJoystickDriverCLI
import OpenJoystickDriverKit

private var applicationHost: HeadlessApplicationHost?

// The executable runs as the `ojd` command-line tool when invoked under that name, and as the app
// otherwise.
if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "ojd" {
  let arguments = Array(CommandLine.arguments.dropFirst())
  InstalledCLIForwarder.forwardIfNeeded(arguments: arguments)
  await CLI().run(arguments: arguments)
} else {
  do { try ApplicationServiceLogService.beginCurrentSessionCapture() } catch {
    fputs("[OpenJoystickDriver] Log capture unavailable: \(error.localizedDescription)\n", stderr)
  }
  applicationHost = HeadlessApplicationHost()
  applicationHost?.run()
}
