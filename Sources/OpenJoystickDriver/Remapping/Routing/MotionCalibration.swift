import OpenJoystickDriverKit

extension RemappingOutputRouter {
  func motionCalibration(
    for runtimeIdentifier: String,
    command: RemappingMotionCalibrationCommand? = nil
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let lease = try outputLeaseIfOpen() else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    do {
      try await synchronizeControls(requiring: lease.permit)
      let status = try await core.motionCalibration(
        for: runtimeIdentifier,
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
  func motionCalibration(
    for runtimeIdentifier: String,
    command: RemappingMotionCalibrationCommand?,
    requiring permit: RemappingEmissionPermit
  ) async throws -> RemappingMotionCalibrationStatus {
    defer { schedulingRevision &+= 1 }
    try requireOperationalPermit(permit)
    guard
      let identifier = connectedIdentifiers.first(where: {
        $0.runtimeIdentifier == runtimeIdentifier
      })
    else { throw RemappingMotionCalibrationError.controllerUnavailable }
    let pair = pairSession(for: identifier)
    if let pair {
      switch pair.profile.joyConPair?.gyroSelection {
      case .left where identifier != pair.left, .right where identifier != pair.right, .disabled,
        .none:
        throw RemappingMotionCalibrationError.motionUnavailable
      case .left, .right: break
      }
    }
    let engineIdentifier = pair?.left ?? identifier
    let sessionID = await engine.motionSessionIdentifier(for: engineIdentifier)
    try await reconcileEligibility(for: identifier, requiring: permit)
    try requireOperationalPermit(permit)
    guard connectedIdentifiers.contains(identifier), let route = routes[identifier] else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    guard case .remapping(let profile) = route.selection, route.eligibility == .eligible else {
      throw RemappingMotionCalibrationError.motionUnavailable
    }
    guard let sessionID, await engine.motionSessionIdentifier(for: engineIdentifier) == sessionID
    else { throw RemappingMotionCalibrationError.motionUnavailable }
    try requireOperationalPermit(permit)
    if let command {
      return try await engine.calibrateMotion(
        command,
        for: engineIdentifier,
        requiring: permit,
        expectedSessionID: sessionID
      )
    }
    guard let status = await engine.motionCalibrationStatus(for: engineIdentifier) else {
      throw RemappingMotionCalibrationError.motionUnavailable
    }
    try requireOperationalPermit(permit)
    guard await engine.motionSessionIdentifier(for: engineIdentifier) == sessionID else {
      throw RemappingMotionCalibrationError.motionUnavailable
    }
    try requireOperationalPermit(permit)
    guard connectedIdentifiers.contains(identifier),
      case .remapping(let currentProfile) = routes[identifier]?.selection,
      currentProfile == profile, routes[identifier]?.eligibility == .eligible
    else { throw RemappingMotionCalibrationError.motionUnavailable }
    return status
  }
}
