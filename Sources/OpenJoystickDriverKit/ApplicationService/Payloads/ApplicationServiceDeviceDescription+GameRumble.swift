import Foundation

extension VirtualHIDProfileID {
  /// Whether a game can rumble a controller through this persona: its descriptor declares the
  /// rumble output report that the consumer output codec decodes. `Generic` declares none.
  public var carriesRumble: Bool { makeProfile().reportFormat.outputReportPayloadSize != nil }
}

extension ApplicationServiceDeviceDescription {
  /// The persona that serves the controller when the controller has rumble motors and that
  /// persona carries no rumble, so no game can rumble the controller; nil otherwise.
  ///
  /// The persona is a user's choice or automatic selection's, so the controller keeps it and the
  /// caller states the loss instead.
  public var personaWithoutGameRumble: VirtualHIDProfileID? {
    guard physicalOutputCapabilities.supportsRumble,
      let profile = servingDecision.selection?.profileID, !profile.carriesRumble
    else { return nil }
    return profile
  }
}
