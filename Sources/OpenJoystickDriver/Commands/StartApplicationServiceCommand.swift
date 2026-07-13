import Foundation
import OpenJoystickDriverKit

struct StartApplicationServiceCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Start")
    do {
      try ApplicationServiceManager.start()
      let client = ApplicationServiceClient()
      client.connect()
      guard client.isConnected else {
        print("Failed to launch the main application.")
        exit(1)
      }
      print("Main application is running.")
    } catch {
      print("Failed to start main application: \(error.localizedDescription)")
      exit(1)
    }
  }
}
