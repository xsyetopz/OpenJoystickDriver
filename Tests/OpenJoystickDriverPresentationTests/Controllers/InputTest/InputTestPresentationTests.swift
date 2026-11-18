import AppKit
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct InputTestPresentationTests {
  @Test
  func inputTestWindowUsesRequestedStableSizing() {
    #expect(InputTestWindowSizingPolicy.defaultContentSize == NSSize(width: 900, height: 620))
    #expect(InputTestWindowSizingPolicy.minimumContentSize == NSSize(width: 700, height: 500))
    #expect(
      InputTestWindowSizingPolicy.fittingContentSize(NSSize(width: 640, height: 420))
        == InputTestWindowSizingPolicy.minimumContentSize
    )
  }

  @Test(arguments: ServingFixture.all)
  func windowTitleNamesPhysicalController(_ fixture: ServingFixture) {
    let device = fixture.device
    let title = InputTestWindowTitle.make(for: device)
    #expect(title == "Input Test — \(fixture.name)")
    if let published = device.publishedVirtualProfile {
      #expect(!title.contains(published.productName))
    }
  }

  @Test
  func dpadDirectionsHaveDistinctSymbols() {
    let symbols = RemappingDpadDirection.allCases.map(InputTestButtonPresentation.dpadSymbol)
    #expect(Set(symbols).count == RemappingDpadDirection.allCases.count)
  }

  @Test
  func controlsOutsideDrawnClustersAreListedAsAdditional() {
    var state = ControllerState.neutral
    state.hat = .north
    state.pressed = [
      .leftShoulder, .leftStickClick, .leftTrigger, .auxiliary1, .auxiliary2, .leftPaddle1,
      .rightPaddle1, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .microphone,
    ]

    #expect(
      InputTestButtonPresentation.additionalControls(in: state) == [
        .microphone, .leftPaddle1, .rightPaddle1, .auxiliary1, .auxiliary2, .auxiliary3,
        .auxiliary4, .auxiliary5, .auxiliary6,
      ]
    )
    #expect(
      InputTestButtonPresentation.localizedTitle(for: .auxiliary1)
        == RuntimePresentation.sourceLabel(.button(.auxiliary1))
    )
  }

  @Test
  func controllerFamiliesSelectProtocolAppropriateInputSymbols() {
    let xbox = InputTestControllerSymbolSet.resolve(for: .xbox)
    #expect(xbox.leftShoulder.symbol == "lb.button.roundedbottom.horizontal")
    #expect(xbox.leftTrigger.symbol == "lt.button.roundedtop.horizontal")
    #expect(xbox.guide.symbol == "xbox.logo")
    #expect(xbox.leftStickClick.symbol == "lsb.button.angledbottom.horizontal.left")

    let generic = InputTestControllerSymbolSet.resolve(for: .generic)
    #expect(generic.leftShoulder.symbol == nil)
    #expect(generic.leftShoulder.fallbackText == "LB / L1")
    #expect(generic.guide.symbol == "house.fill")
  }

  @Test
  func captureIsListedAsAdditionalAndBackIsDrawn() {
    var state = ControllerState.neutral
    state.pressed = [.back, .guide, .capture]

    #expect(InputTestButtonPresentation.additionalControls(in: state) == [.capture])
  }
}
