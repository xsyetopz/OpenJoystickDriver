import Dispatch
import Foundation
import OpenJoystickDriverCLI
import OpenJoystickDriverKit

// `ojd generate` starts this executable as the process that runs a generator script.
GenerateHelper.runAndExitIfRequested()

// The host adapter lives below `platform/`; everything here reaches it through `PlatformHost`.
installPlatformHost()

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
  PlatformHosts.current.runApplication()
}
