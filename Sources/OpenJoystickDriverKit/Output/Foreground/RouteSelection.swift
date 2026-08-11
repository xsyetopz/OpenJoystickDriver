import Foundation

/// Chooses which Compatibility route should receive live controller state.
public enum ForegroundConsumerRouteSelection {
  /// Returns the only consumer bundle whose dedicated route should remain allocated.
  public static func retainedDedicatedBundleRootPaths(
    frontmostBundleRootPath: String?,
    effectiveConsumerBundleRoots: Set<String>,
    observedConsumerBundleRoots: Set<String>,
    activeRouteToken: String?
  ) -> Set<String> {
    guard activeRouteToken != nil, let frontmostBundleRootPath else { return [] }
    let consumers = effectiveConsumerBundleRoots.union(observedConsumerBundleRoots)
    return consumers.contains(frontmostBundleRootPath) ? [frontmostBundleRootPath] : []
  }

  public static func activeRouteToken(
    frontmostBundleRootPath: String?,
    effectiveConsumerBundleRoots: Set<String>,
    clients: [ForegroundConsumerClientSample]
  ) -> String? {
    guard let frontmostBundleRootPath else { return nil }
    guard effectiveConsumerBundleRoots.contains(frontmostBundleRootPath) else { return nil }

    // Route ownership is derived from the focused bundle, not from whichever
    // routes the app currently has clients attached to. Some apps attach HID
    // clients to every exposed Compatibility route, so observed client routing
    // is not stable enough to choose the live output path.
    return UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
      forConsumerBundleRootPath: frontmostBundleRootPath
    )
  }
}
