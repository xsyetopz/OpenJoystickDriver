import Foundation
import OpenJoystickDriverKit

extension RemappingOutputRouter {
  /// Reads or changes the motion calibration of `identifier`.
  ///
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when output is closed, and the
  ///   failures of ``RemappingRoutingCore/motionCalibration(for:command:requiring:)``.
  func motionCalibration(
    for identifier: LogicalControllerID,
    command: RemappingMotionCalibrationCommand? = nil
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let lease = try outputLeaseIfOpen() else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    do {
      try await synchronizeControls(requiring: lease.permit)
      let status = try await core.motionCalibration(
        for: identifier,
        command: command,
        requiring: lease.permit
      )
      await reconcileTickerWithEngine()
      return status
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
  }
}

extension RemappingRoutingCore {
  /// Reads the motion calibration status of `identifier`, or applies `command` to it.
  ///
  /// The controller needs a remapping route that is eligible. A paired Joy-Con needs to be the one
  /// that supplies the gyro.
  ///
  /// - Throws: ``RemappingMotionCalibrationError`` when the controller or its motion is
  ///   unavailable, and ``RemappingMotionCalibrationRefusal`` when the gyro is not selected, the
  ///   profile is inactive or the motion session changed.
  func motionCalibration(
    for identifier: LogicalControllerID,
    command: RemappingMotionCalibrationCommand?,
    requiring permit: RemappingEmissionPermit
  ) async throws -> RemappingMotionCalibrationStatus {
    defer { schedulingRevision &+= 1 }
    try requireOperationalPermit(permit)
    guard connectedIdentifiers.contains(identifier)
    else { throw RemappingMotionCalibrationError.controllerUnavailable }
    let pair = pairSession(for: identifier)
    if let pair { try requireGyroSelected(by: pair, identifier: identifier) }
    let engineIdentifier = pair?.left ?? identifier
    let sessionID = await engine.motionSessionIdentifier(for: engineIdentifier)
    try await reconcileEligibility(for: identifier, requiring: permit)
    try requireOperationalPermit(permit)
    guard connectedIdentifiers.contains(identifier), let route = routes[identifier] else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    guard case .remapping(let profile) = route.selection, route.eligibility == .eligible else {
      throw RemappingMotionCalibrationRefusal.profileInactive
    }
    guard let sessionID else { throw RemappingMotionCalibrationError.motionUnavailable }
    guard await engine.motionSessionIdentifier(for: engineIdentifier) == sessionID
    else { throw RemappingMotionCalibrationRefusal.sessionChanged }
    try requireOperationalPermit(permit)
    if let command {
      return try await engine.calibrateMotion(
        command,
        for: engineIdentifier,
        requiring: permit,
        expectedSessionID: sessionID
      )
    }
    return try await readMotionCalibrationStatus(
      for: identifier,
      engineIdentifier: engineIdentifier,
      sessionID: sessionID,
      profile: profile,
      requiring: permit
    )
  }

  /// Throws when the gyro of a paired Joy-Con is not the one of `identifier`.
  private func requireGyroSelected(
    by pair: RemappingJoyConPairSession,
    identifier: LogicalControllerID
  ) throws {
    switch pair.profile.joyConPair?.gyroSelection {
    case .left where identifier != pair.left, .right where identifier != pair.right, .disabled,
      .none:
      throw RemappingMotionCalibrationRefusal.gyroNotSelected
    case .left, .right: break
    }
  }

  /// Reads the status, then checks that the permit, the motion session and the route still hold.
  private func readMotionCalibrationStatus(
    for identifier: LogicalControllerID,
    engineIdentifier: LogicalControllerID,
    sessionID: UUID,
    profile: RemappingProfile,
    requiring permit: RemappingEmissionPermit
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let status = await engine.motionCalibrationStatus(for: engineIdentifier) else {
      throw RemappingMotionCalibrationError.motionUnavailable
    }
    try requireOperationalPermit(permit)
    guard await engine.motionSessionIdentifier(for: engineIdentifier) == sessionID else {
      throw RemappingMotionCalibrationRefusal.sessionChanged
    }
    try requireOperationalPermit(permit)
    guard connectedIdentifiers.contains(identifier),
      case .remapping(let currentProfile) = routes[identifier]?.selection,
      currentProfile == profile, routes[identifier]?.eligibility == .eligible
    else { throw RemappingMotionCalibrationRefusal.sessionChanged }
    return status
  }
}
