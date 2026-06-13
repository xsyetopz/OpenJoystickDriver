import Testing

@testable import OpenJoystickDriverKit

struct ForegroundConsumerRouteSelectionTests {
  @Test
  func testFrontmostConsumerUsesOwnDedicatedRouteEvenWhenClientsAttachToOtherRoutes() {
    let consumerA = "/Applications/ConsumerA.app"
    let consumerB = "/Applications/ConsumerB.app"

    let activeRoute = ForegroundConsumerRouteSelection.activeRouteToken(
      frontmostBundleRootPath: consumerA,
      effectiveConsumerBundleRoots: [consumerA],
      clients: [
        .sample(id: 1, route: UserSpaceVirtualDeviceConstants.sharedRouteToken, bundle: consumerA),
        .sample(
          id: 2,
          route: UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
            forConsumerBundleRootPath: consumerB
          ),
          bundle: consumerA
        ),
        .sample(
          id: 3,
          route: UserSpaceVirtualDeviceConstants.dedicatedRouteToken(
            forConsumerBundleRootPath: consumerB
          ),
          bundle: consumerB
        ),
      ]
    )

    #expect(
      activeRoute
        == UserSpaceVirtualDeviceConstants.dedicatedRouteToken(forConsumerBundleRootPath: consumerA)
    )
  }

  @Test
  func testSingleUnbundledConsumerUsesOwnRouteWhenNoFrontmostBundleMatches() {
    let tool = "/tmp/ojd-sdl3-probe"

    let activeRoute = ForegroundConsumerRouteSelection.activeRouteToken(
      frontmostBundleRootPath: "/Applications/Terminal.app",
      effectiveConsumerBundleRoots: [tool],
      clients: [
        .sample(id: 1, route: UserSpaceVirtualDeviceConstants.sharedRouteToken, bundle: tool)
      ]
    )

    #expect(
      activeRoute
        == UserSpaceVirtualDeviceConstants.dedicatedRouteToken(forConsumerBundleRootPath: tool)
    )
  }

  @Test
  func testMultipleUnbundledConsumersDoNotChooseAmbiguousRoute() {
    let activeRoute = ForegroundConsumerRouteSelection.activeRouteToken(
      frontmostBundleRootPath: "/Applications/Terminal.app",
      effectiveConsumerBundleRoots: ["/tmp/tool-a", "/tmp/tool-b"],
      clients: [
        .sample(
          id: 1,
          route: UserSpaceVirtualDeviceConstants.sharedRouteToken,
          bundle: "/tmp/tool-a"
        ),
        .sample(
          id: 2,
          route: UserSpaceVirtualDeviceConstants.sharedRouteToken,
          bundle: "/tmp/tool-b"
        ),
      ]
    )

    #expect(activeRoute == nil)
  }
}

private extension ForegroundConsumerClientSample {
  static func sample(
    id: UInt64,
    route: String,
    bundle: String,
    opened: Bool = true,
    suspended: Bool = false
  ) -> Self {
    .init(
      clientID: id,
      routeToken: route,
      bundleRootPath: bundle,
      isOpened: opened,
      isSuspended: suspended,
      activitySignature: .init(
        queueHead: 0,
        queueTail: 0,
        queueEntries: 0,
        getReportCount: 0,
        setReportCount: 0,
        setReportErrorCount: 0
      )
    )
  }
}
