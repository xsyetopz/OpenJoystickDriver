import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// The controller detail shows the serving route `ojd controller show` prints as `serving.route`.
@MainActor
struct ServingRouteLabelTests {
  private static func key(for route: ServingRoute) -> String {
    switch route {
    case .nativePassThrough: "platform.macos.ui.controllers.serving.nativePassThrough"
    case .virtualHID: "ui.controllers.serving.virtualHID"
    case .extensionOwned: "ui.controllers.serving.extensionOwned"
    case .outputDisabled: "ui.controllers.serving.outputDisabled"
    }
  }

  /// The fixture as the service describes it; a controller with output off reports why.
  private static func device(_ fixture: ServingFixture) -> ApplicationServiceDeviceDescription {
    var device = fixture.device
    if !fixture.outputEnabled {
      device.publication = ApplicationServicePublicationStatus.notPublished(.outputDisabled)
    }
    return device
  }

  @Test(arguments: ServingFixture.all)
  func detailLabelNamesRouteOfServingPolicy(_ fixture: ServingFixture) {
    let decided = ServingPolicy.decision(fixture.input).route
    #expect(Self.device(fixture).servingRouteLabel == OJDLocalized.string(Self.key(for: decided)))
  }

  @Test
  func everyRouteHasItsOwnLocalizedLabel() {
    let labels = ServingFixture.all.map { fixture in
      Self.key(for: ServingPolicy.decision(fixture.input).route)
    }
    #expect(Set(labels).count == 4)
    for key in Set(labels) { #expect(OJDLocalized.string(key) != key) }
  }
}
