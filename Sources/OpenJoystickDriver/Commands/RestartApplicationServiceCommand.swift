import Darwin
import Foundation
import OpenJoystickDriverKit

struct RestartApplicationServiceCommand {
  func run() {
    requireApplicationsBundleOrExit()
    requireValidBundleSignatureOrExit(action: "Restart main application")
    do {
      if let processIdentifier = LocalServiceRPCClient.serverProcessIdentifier() {
        guard kill(processIdentifier, SIGTERM) == 0 else {
          print("Failed to stop the running main application (errno \(errno)).")
          exit(1)
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, LocalServiceRPCClient.serverProcessIdentifier() != nil {
          Thread.sleep(forTimeInterval: 0.1)
        }
        guard LocalServiceRPCClient.serverProcessIdentifier() == nil else {
          print("The running main application did not stop within 5 seconds.")
          exit(1)
        }
      }

      try ApplicationServiceManager.restart()
      let client = ApplicationServiceClient()
      client.connect()
      guard client.isConnected else {
        print("Login registration refreshed, but the main application did not launch.")
        exit(1)
      }
      print("Main application restarted.")
    } catch {
      print("Failed to restart main application: \(error.localizedDescription)")
      exit(1)
    }
  }
}
