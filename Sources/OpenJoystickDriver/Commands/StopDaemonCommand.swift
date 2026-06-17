import Foundation
import OpenJoystickDriverKit

struct StopDaemonCommand {
  func run() {
    do {
      try DaemonManager.stop()
      print("Daemon stopped.")
    } catch {
      print("Failed to stop daemon: \(error.localizedDescription)")
      exit(1)
    }
  }
}
