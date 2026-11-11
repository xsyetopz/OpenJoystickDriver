import Foundation
import OpenJoystickDriverKit

/// Exports the mapping of a controller's virtual gamepad, as `ojd virtual export-mapping` prints
/// it.
enum VirtualGamepadExport {
  /// Returns the virtual HID profile to export: the one the service selected for `device`.
  ///
  /// Nil when it has none, so there is nothing to map.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The virtual HID profile to export: the one the service selected for `device`.
  static func profile(for device: ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? {
    device.servingDecision.selection?.profileID
  }

  /// Returns the file text of `profile` in `format`, ending with a newline as the command's
  /// standard output does.
  ///
  /// - Parameters:
  ///   - format: The mapping format.
  ///   - profile: The virtual gamepad profile.
  /// - Returns: The file text of `profile` in `format`, ending with a newline as the command's
  ///   standard output does.
  /// - Throws: The error of the mapping when it cannot be built.
  static func document(
    format: VirtualMappingFormat,
    profile: VirtualHIDProfileID
  ) throws
    -> String
  {
    // The file ends with a newline, as the command's standard output does.
    try format.document(for: [profile]) {
      OJDLocalized.formatted("cli.virtual.group.sdlHintsNote", CommandLineName.kebab($0.rawValue))
    } + "\n"
  }

  /// Returns the suggested file name, such as `sdl-compatible-sdl.txt`.
  ///
  /// - Parameters:
  ///   - format: The mapping format.
  ///   - profile: The virtual gamepad profile.
  /// - Returns: The suggested file name, such as `sdl-compatible-sdl.txt`.
  static func fileName(format: VirtualMappingFormat, profile: VirtualHIDProfileID) -> String {
    let name = [profile.rawValue, format.rawValue].map(CommandLineName.kebab).joined(
      separator: "-"
    )
    return "\(name).\(format.fileExtension)"
  }
}
