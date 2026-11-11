import Foundation
public import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// A requested change to one controller model's or unit's stored virtual HID profile override.
  enum VirtualHIDProfileOverrideChange: Sendable {
    /// Store the profile with this raw identifier.
    case set(String)
    /// Return the model or unit to automatic selection.
    case reset
  }

  /// Stores `profile` as the override for the selected controller's model and retargets every
  /// connected controller of that model to it.
  ///
  /// With `unit`, stores it for the selected unit only and retargets only that controller.
  public func setVirtualHIDProfileOverride(
    _ profile: String,
    for controller: ControllerReference,
    unit: Bool = false
  ) async -> VirtualHIDProfileOverrideResult {
    await changeVirtualHIDProfileOverride(.set(profile), for: controller, unit: unit)
  }

  /// Returns the selected controller's model to automatic selection and retargets every connected
  /// controller of that model.
  ///
  /// With `unit`, removes the selected unit's override only, so its model's override applies again,
  /// and retargets only that controller.
  public func resetVirtualHIDProfileOverride(
    for controller: ControllerReference,
    unit: Bool = false
  ) async -> VirtualHIDProfileOverrideResult {
    await changeVirtualHIDProfileOverride(.reset, for: controller, unit: unit)
  }

  /// Applies `change` after every earlier backend activation, override change, and settings
  /// reset, so two changes never interleave their persist-then-retarget steps.
  func changeVirtualHIDProfileOverride(
    _ change: VirtualHIDProfileOverrideChange,
    for controller: ControllerReference,
    unit: Bool = false
  ) async -> VirtualHIDProfileOverrideResult {
    let result = await virtualOutputTransitionCoordinator.enqueueResult {
      [weak self] () -> VirtualHIDProfileOverrideResult? in
      await self?.performVirtualHIDProfileOverrideChange(
        change,
        for: controller,
        unit: unit
      )
    }
    if let outcome = result.flatMap({ $0 }) {
      if outcome.succeeded { NotificationCenter.postServiceStatusChanged(from: self) }
      return outcome
    }
    var requested: VirtualHIDProfileID?
    if case .set(let raw) = change { requested = VirtualHIDProfileID(rawValue: raw) }
    return VirtualHIDProfileOverrideResult(
      requested: requested,
      live: nil,
      source: .automatic,
      failure: .serverStopped
    )
  }

  /// Applies `change` to the stored override of `controller` and retargets the controllers it
  /// covers.
  private func performVirtualHIDProfileOverrideChange(
    _ change: VirtualHIDProfileOverrideChange,
    for controller: ControllerReference,
    unit: Bool
  ) async -> VirtualHIDProfileOverrideResult {
    let target = await overrideTarget(controller, unit: unit)
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
    var matches = await connectedControllers(of: target.model)
    var scope = OverrideScope(model: target.model, unit: nil)
    if unit {
      guard
        let unitIdentifier = ControllerPortKey.of(target, installationKey: installationKey)?
          .rawValue
      else {
        return result(requested, .controllerNotFound)
      }
      scope.unit = unitIdentifier
      matches = [target]
    }
    let prior = virtualHIDProfileOverrides.storedOverride(
      vendorID: scope.model.vendorID,
      productID: scope.model.productID,
      unit: scope.unit
    )
    do { try storeVirtualHIDProfileOverride(requested, for: scope) } catch {
      if case .keptFile(let path) = error {
        return result(requested, .overrideFileKept(path: path))
      }
      return result(requested, .persistenceFailed)
    }
    guard let automatic = automaticUserSpaceDispatcher() else {
      return result(requested, .outputDisabled)
    }
    if let failure = await retargetModel(matches, with: automatic, restoring: prior, for: scope) {
      return result(requested, failure)
    }
    guard
      let selection = automatic.profileState(for: target).selection
    else { return result(requested, .controllerNotFound) }
    if case .automaticAfterRejecting = selection.source {
      return result(requested, .overrideRejectedByController)
    }
    return result(requested, nil)
  }

  /// Retargets every controller in `matches`.
  ///
  /// When one fails, restores `prior` as the scope's stored override, returns the already switched
  /// controllers to it, and names the failure.
  private func retargetModel(
    _ matches: [LogicalControllerID],
    with automatic: AutomaticUserSpaceOutputDispatcher,
    restoring prior: VirtualHIDProfileID?,
    for scope: OverrideScope
  ) async -> VirtualHIDProfileOverrideFailure? {
    var switched: [LogicalControllerID] = []
    for identifier in matches {
      do {
        try await retargetWithinTimeout(identifier, with: automatic)
        switched.append(identifier)
      } catch {
        var restoreError: (any Error)?
        do { try storeVirtualHIDProfileOverride(prior, for: scope) } catch let failure {
          restoreError = failure
        }
        for pad in switched { try? await retargetWithinTimeout(pad, with: automatic) }
        return await retargetFailure(error, of: identifier, restoreError: restoreError)
      }
    }
    return nil
  }

  /// Retargets one controller within the per-controller timeout.
  ///
  /// A retarget that finishes after the timeout runs again, after every change queued by then, so
  /// the controller follows the stored override current at that point.
  /// `AutomaticUserSpaceOutputDispatcher.retarget` records the selection it read before replacing
  /// the backend, so it must not overlap another retarget.
  private func retargetWithinTimeout(
    _ identifier: LogicalControllerID,
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
        return (try? await retargetWithinTimeout(identifier, with: automatic)) != nil
      }
    }
  }

  /// Returns the failure that a failed retarget of `identifier` reports, with the failure to
  /// restore the prior override when there was one.
  private func retargetFailure(
    _ error: any Error,
    of identifier: LogicalControllerID,
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

  /// The stored override a change writes: a controller model's, or one unit's of it.
  private struct OverrideScope {
    /// The controller model whose override changes.
    let model: ControllerModelID
    /// The port key of the unit; nil for the whole model.
    var unit: String?
  }

  /// Stores `profile` as the override of `scope`, or removes the override when it is nil.
  ///
  /// - Throws: ``VirtualHIDProfileOverrideError`` when the override file cannot be written.
  private func storeVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID?,
    for scope: OverrideScope
  ) throws(VirtualHIDProfileOverrideError) {
    if let profile {
      try virtualHIDProfileOverrides.set(
        profile,
        vendorID: scope.model.vendorID,
        productID: scope.model.productID,
        unit: scope.unit
      )
    } else {
      try virtualHIDProfileOverrides.reset(
        vendorID: scope.model.vendorID,
        productID: scope.model.productID,
        unit: scope.unit
      )
    }
  }

  /// The controller whose override changes.
  ///
  /// A model override applies to every controller of the model, so a model reference names any of
  /// them; a unit override needs exactly one controller.
  private func overrideTarget(
    _ controller: ControllerReference,
    unit: Bool
  ) async -> LogicalControllerID? {
    let matches: [LogicalControllerID]
    switch controller {
    case .session:
      return await deviceManager.connectedIdentifier(for: controller)
    case .port(let portKey):
      matches = await connectedIdentifierProvider().filter {
        ControllerPortKey.of($0, installationKey: installationKey) == portKey
      }
    case .model(let model):
      matches = await connectedControllers(of: model)
      if !unit { return matches.first }
    }
    return matches.count == 1 ? matches.first : nil
  }

  /// Every connected controller of the model, sorted.
  private func connectedControllers(of model: ControllerModelID) async -> [LogicalControllerID] {
    await connectedIdentifierProvider().filter { $0.model == model }.sorted()
  }

  /// Builds the result of an override change from the selection that `identifier` has.
  private func virtualHIDProfileOverrideResult(
    requested: VirtualHIDProfileID?,
    for identifier: LogicalControllerID?,
    failure: VirtualHIDProfileOverrideFailure?
  ) -> VirtualHIDProfileOverrideResult {
    let automatic = automaticUserSpaceDispatcher()
    let selection = identifier.flatMap {
      automatic?.profileState(for: $0).selection
    }
    let stored = identifier.flatMap {
      virtualHIDProfileOverrides.override(
        vendorID: $0.model.vendorID,
        productID: $0.model.productID,
        unit: ControllerPortKey.of($0, installationKey: installationKey)?.rawValue
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
      source: source.reported,
      failure: failure
    )
  }

  /// The live automatic dispatcher; nil while virtual output is disabled.
  func automaticUserSpaceDispatcher() -> AutomaticUserSpaceOutputDispatcher? {
    userSpaceLock.withLock {
      userSpaceEnabled ? userSpaceDispatcher as? AutomaticUserSpaceOutputDispatcher : nil
    }
  }

  /// Describes each controller with its virtual HID profile selection and stored override.
  func describingVirtualHIDProfiles(
    _ controllers: [(identifier: LogicalControllerID, device: ApplicationServiceDeviceDescription)]
  ) async -> [ApplicationServiceDeviceDescription] {
    let automatic = automaticUserSpaceDispatcher()
    var result: [ApplicationServiceDeviceDescription] = []
    for (identifier, device) in controllers {
      var described = device
      described.paused = await remappingRouter.isPaused(identifier)
      described.profileInForce = await remappingRouter.profileInForce(for: identifier)
      let unitOverride = device.portKey.flatMap {
        virtualHIDProfileOverrides.storedOverride(
          vendorID: device.vendorID,
          productID: device.productID,
          unit: $0.rawValue
        )
      }
      let override =
        unitOverride
        ?? virtualHIDProfileOverrides.override(
          vendorID: device.vendorID,
          productID: device.productID
        )
      // The serving policy decides the route and the persona; the dispatcher only carries it out.
      // A controller the system serves, or one with output off, has no selection.
      let decision = ServingPolicy.decision(
        ServingInput(device, outputEnabled: automatic != nil, override: override)
      )
      let unavailable = decision.route == .outputDisabled(.noVirtualProfile)
      described.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
        profile: decision.selection?.profileID,
        source: decision.selection?.source.reported,
        override: override,
        overrideScope: override == nil ? nil : unitOverride == nil ? .model : .unit,
        unavailable: unavailable
      )
      described.publication = Self.publication(
        of: device,
        identifier: identifier,
        automatic: automatic,
        unavailable: unavailable
      )
      result.append(described)
    }
    return result
  }

  /// The publication reason a route gives for publishing nothing; nil when the route publishes a
  /// persona (`virtualHID`, and `extensionOwned`, whose extension owns the USB link while OJD
  /// publishes the virtual device) and publication is left to the session and profile checks.
  static func notPublishedReason(
    of route: ServingRoute,
    observation: ControllerOwnershipObservation
  ) -> ApplicationServicePublicationStatus.NotPublishedReason? {
    switch route {
    case .nativePassThrough:
      observation == .systemGamepad ? .systemGamepad : .nativeHIDPassThrough
    case .outputDisabled(.upstreamVirtualDevice): .upstreamVirtualDevice
    case .outputDisabled(.userDisabled): .outputDisabled
    case .outputDisabled(.noVirtualProfile), .virtualHID, .extensionOwned: nil
    }
  }

  /// Whether a virtual device publishes `device`, with the first reason it does not.
  static func publication(
    of device: ApplicationServiceDeviceDescription,
    identifier: LogicalControllerID,
    automatic: AutomaticUserSpaceOutputDispatcher?,
    unavailable: Bool
  ) -> ApplicationServicePublicationStatus {
    let notPublished = { (reason: ApplicationServicePublicationStatus.NotPublishedReason) in
      ApplicationServicePublicationStatus.notPublished(reason)
    }
    guard let automatic else { return notPublished(.outputDisabled) }
    let recorded = automatic.publicationStatus(for: identifier)
    if let recorded, recorded.state != .notPublished { return recorded }
    let route = ServingPolicy.route(for: device, override: recorded?.target)
    if let reason = Self.notPublishedReason(of: route, observation: device.physicalOwnership) {
      return notPublished(reason)
    }
    if device.sessionState == .suspended { return notPublished(.sessionSuspended) }
    if unavailable { return notPublished(.noVirtualProfile) }
    return recorded ?? notPublished(.noInputYet)
  }

  /// Clears every virtual HID profile override; false when the persona directory cannot be read
  /// or a persona file stays, and each kept file is logged.
  func resetVirtualHIDProfileSettings() -> Bool {
    defer { NotificationCenter.postServiceStatusChanged(from: self) }
    do {
      let kept = try virtualHIDProfileOverrides.resetAll()
      for path in kept { unsafe fputs("[VirtualDevices] Reset kept \(path)\n", unsafe stderr) }
      return kept.isEmpty
    } catch {
      unsafe fputs("[VirtualDevices] Reset failed: \(error.statusDescription)\n", unsafe stderr)
      return false
    }
  }

  /// Applies a change to the persona files.
  ///
  /// A connected controller whose persona identity or profile changed gets a replacement virtual
  /// device, and the others keep theirs.
  func reloadPersonas() async {
    let retargeted = await virtualOutputTransitionCoordinator.enqueueResult { [weak self] in
      guard let self else { return true }
      return await retargetConnectedControllers()
    }
    if retargeted == false {
      unsafe fputs("[VirtualDevices] A controller kept its earlier virtual device\n", stderr)
    }
    NotificationCenter.postServiceStatusChanged(from: self)
  }

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
