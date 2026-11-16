import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct AccessPresentationTests {
  @Test
  func signedClientWithoutPublisherIDNamesMissingPublisher() {
    #expect(
      AccessPresentation.signer(.signed, nil)
        == OJDLocalized.string("ui.access.signer.signedUnknownPublisher")
    )
    #expect(
      AccessPresentation.signer(.signed, "TEAM123")
        == OJDLocalized.formatted("ui.access.signer.signed", "TEAM123")
    )
  }

  @Test
  func enabledWebEndpointWithoutPortSaysNoPortIsChosen() {
    let web = AccessWebStatus(enabled: true, listening: false, port: nil, pagesPath: "/tmp/pages")
    #expect(AccessPresentation.web(web) == OJDLocalized.string("ui.access.web.noPort"))
  }

  @Test
  func webEndpointStatesNamePort() {
    let closed = AccessWebStatus(enabled: true, listening: false, port: 4_321, pagesPath: "/p")
    #expect(
      AccessPresentation.web(closed) == OJDLocalized.formatted("ui.access.web.closed", "4321")
    )
    let on = AccessWebStatus(enabled: true, listening: true, port: 4_321, pagesPath: "/p")
    #expect(
      AccessPresentation.web(on)
        == OJDLocalized.formatted(
          "ui.access.web.on",
          "ws://127.0.0.1:4321/endpoint",
          "http://127.0.0.1:4321/"
        )
    )
  }
}
