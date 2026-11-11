import Foundation

/// The physical-output path: the manager takes output commands for a connected controller.
extension DeviceManager: OutputSink {
  /// The destination that this sink delivers to: the physical output of a controller.
  nonisolated public var destination: OutputDestination { .physicalOutput }

  /// Sends a controller output command to the connected controller.
  ///
  /// - Throws: `StreamBoundaryError.rejected` when the controller does not deliver the command.
  public func consume(
    _ command: ControllerOutputCommand,
    for controller: LogicalControllerID
  )
    async throws
  {
    let result = await sendControllerOutput(command, toConnected: controller)
    guard result.outcome == .delivered else {
      throw StreamBoundaryError.rejected(.physicalOutput, result.outcome.rawValue)
    }
  }

  /// Applies a mapping output claim to the controller.
  ///
  /// - Throws: `StreamBoundaryError.rejected` when the claim is not applied.
  public func consume(_ claim: MappingOutputClaim, for controller: LogicalControllerID) async throws
  {
    let applied = await setMappingPhysicalOutput(
      claim.output,
      active: claim.active,
      owner: claim.owner,
      for: controller
    )
    guard applied else {
      throw StreamBoundaryError.rejected(.physicalOutput, "mapping output not applied")
    }
  }

  /// Releases every mapping output of the controller.
  ///
  /// - Throws: `StreamBoundaryError.rejected` when the outputs are not released.
  public func consume(
    _: MappingOutputRelease,
    for controller: LogicalControllerID
  ) async throws {
    guard await releaseMappingPhysicalOutputs(for: controller) else {
      throw StreamBoundaryError.rejected(.physicalOutput, "mapping outputs not released")
    }
  }

  /// Applies the profile color claim to the controller.
  ///
  /// - Throws: `StreamBoundaryError.rejected` when the color is not applied.
  public func consume(_ color: ProfileColorClaim, for controller: LogicalControllerID) async throws
  {
    guard await setProfilePhysicalColor(color.color, for: controller) else {
      throw StreamBoundaryError.rejected(.physicalOutput, "profile colour not applied")
    }
  }
}
