/// Stable local RPC method names; each raw value is the method name on the wire.
package enum ApplicationServiceRPCMethod: String, CaseIterable, Sendable {
  /// Reads the service's status.
  case getStatus
  /// Asks macOS for every permission the service requires.
  case requestRequiredAccess
  /// Asks macOS for one permission.
  case requestAccess
  /// Reads a controller's input state.
  case getControllerState
  /// Reads a controller's packet log.
  case getPacketLog
  /// Reads the values a controller's virtual gamepad last reported.
  case getVirtualOutputState
  /// Sends an output command to a controller.
  case sendControllerOutput
  /// Previews a color on a physical controller.
  case previewPhysicalColor
  /// Ends a physical color preview.
  case releasePhysicalColorPreview
  /// Reads the diagnostics of the virtual devices.
  case getVirtualDeviceDiagnostics
  /// Reads the frame timings of the connected controllers.
  case getFrameTimings
  /// Waits until the service's status changes, a hold time passes or a test notification is
  /// announced.
  case waitForServiceStatusChange
  /// Asks the service to announce a test notification to the app.
  case sendTestNotification
  /// Reports how a test notification ended.
  case reportTestNotificationResult
  /// Sets a virtual HID profile override.
  case setVirtualHIDProfileOverride
  /// Returns a controller to automatic virtual HID profile selection.
  case resetVirtualHIDProfileOverride
  /// Sets who serves a controller model.
  case setControllerServer
  /// Sets a tuning value of a controller model.
  case setControllerTuning
  /// Opens a virtual feed.
  case openVirtualFeed
  /// Exchanges frames and output commands with a virtual feed.
  case exchangeVirtualFeed
  /// Closes a virtual feed.
  case closeVirtualFeed
  /// Suspends a controller's session.
  case suspendController
  /// Resumes a controller's session.
  case resumeController
  /// Disconnects a wireless controller.
  case disconnectWirelessController
  /// Plays audio on a controller's speaker.
  case playControllerSpeaker
  /// Stops the audio on a controller's speaker.
  case stopControllerSpeaker
  /// Resets the app settings.
  case resetSettings
  /// Reads the app settings.
  case getSettings
  /// Sets one app setting.
  case setSetting
  /// Reads the endpoint's access status.
  case getAccessStatus
  /// Turns the endpoint on or off.
  case setAccessEnabled
  /// Grants a client access to the endpoint.
  case grantAccess
  /// Revokes a client's or token's access.
  case revokeAccess
  /// Grants a token access to the endpoint's WebSocket.
  case grantTokenAccess
  /// Turns the WebSocket on or off.
  case setWebAccess
  /// Reads or changes a controller's motion calibration.
  case remappingMotionCalibration
  /// Pairs two Joy-Con.
  case pairRemappingJoyCons
  /// Unpairs a Joy-Con pair.
  case unpairRemappingJoyCons
  /// Reads the remapping snapshot.
  case getRemappingSnapshot
  /// Reads one remapping profile.
  case getRemappingProfile
  /// Creates a remapping profile.
  case createRemappingProfile
  /// Updates a remapping profile.
  case updateRemappingProfile
  /// Deletes a remapping profile.
  case deleteRemappingProfile
  /// Imports a remapping profile.
  case importRemappingProfile
  /// Activates a remapping profile.
  case activateRemappingProfile
  /// Deactivates the active profile of a controller model.
  case deactivateRemappingProfile
  /// Deactivates a remapping profile by its ID.
  case deactivateRemappingProfileByID
  /// Reads the state of the permission to post input events.
  case getRemappingPostEventAccess
  /// Requests the permission to post input events.
  case requestRemappingPostEventAccess
  /// Deletes a damaged remapping profile.
  case deleteDamagedRemappingProfile
  /// Resets the remapping profile library.
  case resetRemappingProfileLibrary

  /// True for a method whose reply stays open until something happens, so the server cancels it
  /// when its client closes the connection: the status wait, which is held up to the hold time, and
  /// the test notification request, which waits for the app's report.
  ///
  /// Every other method runs to completion even if the client has left, because it changes state
  /// or asks the system for something that must not stop halfway.
  var holdsReplyOpen: Bool {
    switch self {
    case .waitForServiceStatusChange, .sendTestNotification: true
    default: false
    }
  }
}
