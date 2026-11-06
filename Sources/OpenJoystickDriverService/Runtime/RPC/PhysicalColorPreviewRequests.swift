import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Shows the color on the light of `controller` under `token`; false when a component is outside
  /// 0 to 255 or the controller cannot show it.
  public func previewPhysicalColor(
    for controller: ControllerReference,
    token: UUID,
    red: Int,
    green: Int,
    blue: Int
  ) async -> Bool {
    guard let red = UInt8(exactly: red), let green = UInt8(exactly: green),
      let blue = UInt8(exactly: blue)
    else { return false }
    return await deviceManager.previewPhysicalColor(
      for: controller,
      token: token,
      red: red,
      green: green,
      blue: blue
    )
  }

  /// Ends the color preview that `token` holds on `controller`; false when no such preview exists.
  public func releasePhysicalColorPreview(
    for controller: ControllerReference,
    token: UUID
  ) async -> Bool {
    return await deviceManager.releasePhysicalColorPreview(
      for: controller,
      token: token
    )
  }
}
