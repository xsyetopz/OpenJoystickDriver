import Dispatch
import Foundation
import OpenJoystickDriverKit

private var applicationHost: HeadlessApplicationHost?

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--headless") {
  let filtered = args.filter { $0 != "--headless" }
  CLI().run(arguments: filtered[...])
} else if !args.isEmpty {
  CLI().run(arguments: args[...])
} else {
  do {
    try ApplicationServiceLogService.beginCurrentSessionCapture()
  } catch {
    fputs("[OpenJoystickDriver] Log capture unavailable: \(error.localizedDescription)\n", stderr)
  }
  applicationHost = HeadlessApplicationHost()
  applicationHost?.run()
}
