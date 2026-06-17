import Foundation
import OpenJoystickDriverKit

struct CLI {
  func run(arguments: ArraySlice<String>) {
    let args = Array(arguments)
    let command = args.first ?? "run"

    switch command {
    case "list": ListCommand().run()
    case "status": StatusCommand().run()
    case "diag": DiagnoseCommand().run()
    case "user": UserSpaceCommand().run(arguments: Array(args.dropFirst()))
    case "output": OutputModeCommand().run(arguments: Array(args.dropFirst()))
    case "id": CompatibilityCommand().run(arguments: Array(args.dropFirst()))
    case "test": SelfTestCommand().run(arguments: Array(args.dropFirst()))
    case "ext": SystemExtensionCommand().run(arguments: Array(args.dropFirst()))
    case "start": StartDaemonCommand().run()
    case "stop": StopDaemonCommand().run()
    case "restart": RestartDaemonCommand().run()
    case "reset": ResetSettingsCommand().run()
    case "install": InstallCommand().run()
    case "remove": UninstallCommand().run()
    case "run": RunCommand().run()
    case "--help", "-h", "help": printHelp()
    case "--version", "-v", "version": print("OpenJoystickDriver v0.5.0-alpha.5")
    default:
      print("Unknown command: \(command)")
      printHelp()
      exit(1)
    }
  }

  private func printHelp() {
    print(
      """
      OpenJoystickDriver v0.5.0-alpha.5 \
      - macOS gamepad driver

      Usage: OpenJoystickDriver --headless <command>

      Commands:
        run      Start driver input loop (default)
        list     List connected game controllers
        status   Show permissions, output mode, and devices
        diag     Show hardware diagnostics
        user     Turn user virtual gamepad on/off/status
        output   Set output route: driver, user, both, status
        id       Set app identity: sdl2-3, x360-hid, xone-hid, status
        test     Count input events on virtual devices
        ext      Manage DriverKit system extension
        install  Install login helper
        remove   Remove login helper
        start    Start login helper
        stop     Stop login helper without removing it
        restart  Restart login helper
        reset    Reset mode, identity, and output settings

      Options:
        -h, --help     Show this help
        -v, --version  Show version
      """
    )
  }
}
