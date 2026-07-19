import Foundation

struct RunCommand {
  func run() {
    print("[OpenJoystickDriver] Starting compatibility driver runtime...")
    print("[OpenJoystickDriver] Press Ctrl+C to stop.")

    let runtime = ApplicationServiceRuntime()
    runtime.start()
    RunLoop.main.run()
  }
}
