import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// A requested change to one controller model's stored virtual HID profile override.
  enum VirtualHIDProfileOverrideChange: Sendable {
    /// Store the profile with this raw identifier.
    case set(String)
    /// Return the model to automatic selection.
    case reset
  }

  /// Stores `profile` as the override for the selected controller's model and retargets every
  /// connected controller of that model to it.
  public func setVirtualHIDProfileOverride(
    _ profile: String,
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> VirtualHIDProfileOverrideResult {
    await changeVirtualHIDProfileOverride(
      .set(profile),
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  /// Returns the selected controller's model to automatic selection and retargets every connected
  /// controller of that model.
  public func resetVirtualHIDProfileOverride(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> VirtualHIDProfileOverrideResult {
    await changeVirtualHIDProfileOverride(
      .reset,
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  /// Applies `change` after every earlier backend activation, override change, and settings
  /// reset, so two changes never interleave their persist-then-retarget steps.
  func changeVirtualHIDProfileOverride(
    _ change: VirtualHIDProfileOverrideChange,
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> VirtualHIDProfileOverrideResult {
    let result = await virtualOutputTransitionCoordinator.enqueueResult {
      [weak self] () -> VirtualHIDProfileOverrideResult? in
      await self?.performVirtualHIDProfileOverrideChange(
        change,
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: runtimeIdentifier
      )
    }
    if let result = result.flatMap({ $0 }) { return result }
    var requested: VirtualHIDProfileID?
    if case .set(let raw) = change { requested = VirtualHIDProfileID(rawValue: raw) }
    return VirtualHIDProfileOverrideResult(
      requested: requested,
      live: nil,
      source: VirtualHIDProfileSelector.Selection.Source.automatic.wireName,
      failure: .serverStopped
    )
  }

  private func performVirtualHIDProfileOverrideChange(
    _ change: VirtualHIDProfileOverrideChange,
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> VirtualHIDProfileOverrideResult {
    let matches = await connectedControllers(vendorID: vendorID, productID: productID)
    let target: DeviceIdentifier?
    if let runtimeIdentifier {
      target = matches.first { $0.runtimeIdentifier == runtimeIdentifier }
    } else {
      target = matches.first
    }
    func result(
      _ requested: VirtualHIDProfileID?,
      _ failure: VirtualHIDProfileOverrideFailure?
    ) -> VirtualHIDProfileOverrideResult {
      virtualHIDProfileOverrideResult(requested: requested, for: target, failure: failure)
    }
    let requested: VirtualHIDProfileID?
    switch change {
    case .set(let raw):
      guard let profile = VirtualHIDProfileID(rawValue: raw) else {
        return result(nil, .unknownProfile)
      }
      requested = profile
    case .reset: requested = nil
    }
    guard let target else { return result(requested, .controllerNotFound) }
    let model = target.controllerIdentity
    let prior = virtualHIDProfileOverrides.override(
      vendorID: model.vendorID,
      productID: model.productID
    )
    do { try storeVirtualHIDProfileOverride(requested, for: model) } catch {
      return result(requested, .persistenceFailed)
    }
    guard let automatic = automaticUserSpaceDispatcher() else {
      return result(requested, .outputDisabled)
    }
    if let failure = await retargetModel(matches, with: automatic, restoring: prior, for: model) {
      return result(requested, failure)
    }
    guard
      let selection = automatic.profileState(runtimeIdentifier: target.runtimeIdentifier).selection
    else { return result(requested, .controllerNotFound) }
    if case .automaticAfterRejecting = selection.source {
      return result(requested, .overrideRejectedByController)
    }
    return result(requested, nil)
  }

  /// Retargets every controller in `matches`. When one fails, restores `prior` as the model's
  /// stored override, returns the already switched controllers to it, and names the failure.
  private func retargetModel(
    _ matches: [DeviceIdentifier],
    with automatic: AutomaticUserSpaceOutputDispatcher,
    restoring prior: VirtualHIDProfileID?,
    for model: ControllerIdentity
  ) async -> VirtualHIDProfileOverrideFailure? {
    var switched: [DeviceIdentifier] = []
    for identifier in matches {
      do {
        try await retargetWithinTimeout(identifier, with: automatic)
        switched.append(identifier)
      } catch {
        var restoreError: (any Error)?
        do { try storeVirtualHIDProfileOverride(prior, for: model) } catch let failure {
          restoreError = failure
        }
        for pad in switched { try? await retargetWithinTimeout(pad, with: automatic) }
        return await retargetFailure(error, of: identifier, restoreError: restoreError)
      }
    }
    return nil
  }

  /// Retargets one controller within the per-controller timeout. A retarget that finishes after
  /// the timeout runs again, after every change queued by then, so the controller follows the
  /// stored override current at that point. `AutomaticUserSpaceOutputDispatcher.retarget` records
  /// the selection it read before replacing the backend, so it must not overlap another retarget.
  private func retargetWithinTimeout(
    _ identifier: DeviceIdentifier,
    with automatic: AutomaticUserSpaceOutputDispatcher
  ) async throws {
    try await withVirtualOutputTimeout(
      virtualOutputTransitionTimeouts.perControllerNanoseconds,
      clock: virtualOutputTransitionClock,
      error: .activationTimedOut
    ) {
      try await automatic.retarget(controller: identifier)
    } onLateSuccess: { [weak self] _ in
      _ = await self?.virtualOutputTransitionCoordinator.enqueue { [weak self] in
        guard let self else { return false }
        return (try? await self.retargetWithinTimeout(identifier, with: automatic)) != nil
      }
    }
  }

  private func retargetFailure(
    _ error: any Error,
    of identifier: DeviceIdentifier,
    restoreError: (any Error)?
  ) async -> VirtualHIDProfileOverrideFailure {
    if error is CancellationError {
      if isVirtualOutputServerStopped() { return .serverStopped }
      if await !connectedIdentifierProvider().contains(identifier) { return .controllerNotFound }
    }
    var detail = "\(error)"
    if let restoreError { detail += "; restoring the prior override failed: \(restoreError)" }
    return .activationFailed(detail: detail)
  }

  private func storeVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID?,
    for model: ControllerIdentity
  ) throws(VirtualHIDProfileOverrideError) {
    if let profile {
      try virtualHIDProfileOverrides.set(
        profile,
        vendorID: model.vendorID,
        productID: model.productID
      )
    } else {
      try virtualHIDProfileOverrides.reset(vendorID: model.vendorID, productID: model.productID)
    }
  }

  /// Every connected controller of the model, sorted by runtime identifier.
  private func connectedControllers(vendorID: Int, productID: Int) async -> [DeviceIdentifier] {
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return []
    }
    let model = DeviceIdentifier(vendorID: vendor, productID: product)
    let matches = await connectedIdentifierProvider().filter { $0.modelMatches(model) }
    return matches.sorted { $0.runtimeIdentifier < $1.runtimeIdentifier }
  }

  private func virtualHIDProfileOverrideResult(
    requested: VirtualHIDProfileID?,
    for identifier: DeviceIdentifier?,
    failure: VirtualHIDProfileOverrideFailure?
  ) -> VirtualHIDProfileOverrideResult {
    let automatic = automaticUserSpaceDispatcher()
    let selection = identifier.flatMap {
      automatic?.profileState(runtimeIdentifier: $0.runtimeIdentifier).selection
    }
    let stored = identifier.flatMap {
      virtualHIDProfileOverrides.override(
        vendorID: $0.controllerIdentity.vendorID,
        productID: $0.controllerIdentity.productID
      )
    }
    let source: VirtualHIDProfileSelector.Selection.Source
    if let selection {
      source = selection.source
    } else {
      source = automatic == nil && stored != nil ? .override : .automatic
    }
    return VirtualHIDProfileOverrideResult(
      requested: requested,
      live: selection?.profileID,
      source: source.wireName,
      failure: failure
    )
  }

  /// The live automatic dispatcher; nil while virtual output is disabled.
  func automaticUserSpaceDispatcher() -> AutomaticUserSpaceOutputDispatcher? {
    userSpaceLock.withLock {
      userSpaceEnabled ? userSpaceDispatcher as? AutomaticUserSpaceOutputDispatcher : nil
    }
  }

  /// `devices` with each controller's virtual HID profile selection and stored override.
  func describingVirtualHIDProfiles(
    _ devices: [ApplicationServiceDeviceDescription]
  ) -> [ApplicationServiceDeviceDescription] {
    let automatic = automaticUserSpaceDispatcher()
    return devices.map { device in
      let state = automatic?.profileState(runtimeIdentifier: device.runtimeIdentifier)
      var described = device
      described.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
        profile: state?.selection?.profileID,
        source: state?.selection?.source.wireName,
        override: virtualHIDProfileOverrides.override(
          vendorID: device.vendorID,
          productID: device.productID
        ),
        unavailable: state?.unavailable ?? false
      )
      described.publication = Self.publication(
        of: device,
        automatic: automatic,
        unavailable: state?.unavailable ?? false
      )
      return described
    }
  }

  /// Whether a virtual device publishes `device`, with the first reason it does not.
  private static func publication(
    of device: ApplicationServiceDeviceDescription,
    automatic: AutomaticUserSpaceOutputDispatcher?,
    unavailable: Bool
  ) -> ApplicationServicePublicationStatus {
    let notPublished = { (reason: String) in
      ApplicationServicePublicationStatus(state: .notPublished, reason: reason)
    }
    guard let automatic else { return notPublished("output-disabled") }
    let recorded = automatic.publicationStatus(runtimeIdentifier: device.runtimeIdentifier)
    if let recorded, recorded.state != .notPublished { return recorded }
    switch ControllerExposureDecision.decide(
      ownership: device.physicalOwnership,
      intent: .profile(recorded?.target ?? .generic)
    ).eligibility {
    case .suppressedNativeHIDPassThrough:
      return notPublished(
        device.physicalOwnership == .nativeGamepad ? "native-gamepad" : "native-hid-pass-through"
      )
    case .suppressedUpstreamVirtualDevice: return notPublished("upstream-virtual-device")
    case .suppressedOutputDisabled: return notPublished("output-disabled")
    case .eligible: break
    }
    if device.sessionState == .suspended { return notPublished("session-suspended") }
    if unavailable { return notPublished("no-virtual-profile") }
    return recorded ?? notPublished("no-input-yet")
  }

  /// Clears every virtual HID profile override.
  func resetVirtualHIDProfileSettings() { virtualHIDProfileOverrides.resetAll() }

  /// Reselects every connected controller's profile, each within the per-controller timeout;
  /// false when any replacement failed or timed out.
  func retargetConnectedControllers() async -> Bool {
    guard let automatic = automaticUserSpaceDispatcher() else { return true }
    var succeeded = true
    for identifier in await connectedIdentifiers() {
      do { try await retargetWithinTimeout(identifier, with: automatic) } catch {
        succeeded = false
      }
    }
    return succeeded
  }
}
