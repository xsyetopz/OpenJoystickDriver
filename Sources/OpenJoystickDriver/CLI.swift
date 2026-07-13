import Foundation
import OpenJoystickDriverKit

struct CLI {
  func run(arguments: ArraySlice<String>) {
    let args = Array(arguments)
    let command = args.first ?? "run"

    switch command {
    case "list": ListCommand().run()
    case "status": StatusCommand().run()
    case "input": InputCommand().run(arguments: Array(args.dropFirst()))
    case "logs": LogsCommand().run(arguments: Array(args.dropFirst()))
    case "updates": UpdatesCommand().run(arguments: Array(args.dropFirst()))
    case "permissions": PermissionsCommand().run(arguments: Array(args.dropFirst()))
    case "report": ReportCommand().run(arguments: Array(args.dropFirst()))
    case "diagnose": DiagnoseCommand().run(arguments: Array(args.dropFirst()))
    case "userspace": UserSpaceCommand().run(arguments: Array(args.dropFirst()))
    case "output": OutputModeCommand().run(arguments: Array(args.dropFirst()))
    case "physical-output": PhysicalOutputCommand().run(arguments: Array(args.dropFirst()))
    case "compat": CompatibilityCommand().run(arguments: Array(args.dropFirst()))
    case "selftest": SelfTestCommand().run(arguments: Array(args.dropFirst()))
    case "sysext": SystemExtensionCommand().run(arguments: Array(args.dropFirst()))
    case "start": StartApplicationServiceCommand().run()
    case "restart": RestartApplicationServiceCommand().run()
    case "reset-settings": ResetSettingsCommand().run()
    case "install": InstallCommand().run()
    case "uninstall": UninstallCommand().run()
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

      Usage: OpenJoystickDriver \
      --headless <command>

      Commands:
        run        Start driver \
      (default - processes controller input)
        list       List connected game controllers
        status     Show permission and device status
        input      Inspect or watch normalized input and raw packet logs
        logs       Read or reveal bounded application service log tails
        updates    Check GitHub release metadata without installing
        permissions Inspect or request required HID access
        report     Create a redacted controller support report
        diagnose   Hardware and runtime diagnostics
        userspace  Toggle user-space virtual gamepad (IOHIDUserDevice)
        output     Set output routing mode (DriverKit/user-space)
        physical-output Inspect/test source-controller rumble and player LEDs
        compat     Set compatibility identity (generic-hid/sdl2-3/x360-hid/xone-hid)
        selftest   Count input events on virtual devices
        sysext     Manage DriverKit system extension
        install    Register the main app as a login item
        uninstall  Remove the main app login item
        start      Start application service (register if needed)
        restart    Restart application service
        reset-settings Reset application service settings (mode/identity/output)

      Options:
        -h, --help     Show this help
        -v, --version  Show version
      """
    )
  }
}
