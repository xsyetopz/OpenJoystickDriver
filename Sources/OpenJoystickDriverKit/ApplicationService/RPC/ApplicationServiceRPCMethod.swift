/// Stable local RPC method names; each raw value is the method name on the wire.
package enum ApplicationServiceRPCMethod: String, CaseIterable, Sendable {
  case getStatus
  case requestRequiredAccess
  case requestAccess
  case getControllerState
  case getPacketLog
  case sendControllerOutput
  case previewPhysicalColor
  case releasePhysicalColorPreview
  case setSuppressOutput
  case getVirtualDeviceDiagnostics
  case setVirtualHIDProfileOverride
  case resetVirtualHIDProfileOverride
  case suspendController
  case resumeController
  case disconnectWirelessController
  case resetSettings
  case getSettings
  case setSetting
  case remappingMotionCalibration
  case pairRemappingJoyCons
  case unpairRemappingJoyCons
  case getRemappingSnapshot
  case getRemappingProfile
  case createRemappingProfile
  case updateRemappingProfile
  case deleteRemappingProfile
  case importRemappingProfile
  case activateRemappingProfile
  case deactivateRemappingProfile
  case deactivateRemappingProfileByID
  case getRemappingPostEventAccess
  case requestRemappingPostEventAccess
  case deleteDamagedRemappingProfile
  case resetRemappingProfileLibrary
}
