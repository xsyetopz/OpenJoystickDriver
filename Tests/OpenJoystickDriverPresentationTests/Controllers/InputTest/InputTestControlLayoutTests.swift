import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

extension InputTestTests {
  /// Every control a bundled record declares has a drawing in the live view.
  @Test
  @MainActor
  func liveViewDrawsEveryControlOfEveryBundledRecord() {
    let registry = ProtocolDriverRegistry()
    var missing: [String] = []
    var checked = 0
    for model in ControllerRecordSet.bundled.records.keys.sorted(by: {
      ($0.vendorID, $0.productID) < ($1.vendorID, $1.productID)
    }) {
      guard let declared = registry.profileCapabilities(for: model)?.physicalInput else {
        continue
      }
      checked += 1
      let view = InputTestViewModel(gateway: InputTestGatewayStub())
      view.selectDevice(
        makeInputTestDevice(
          hasMotion: declared.motion,
          controls: declared.controls,
          touchContactCount: declared.touchContactCount
        )
      )
      let undrawn = declared.controls.subtracting(view.controlLayout.drawnControls)
      if !undrawn.isEmpty {
        missing.append("\(model): \(undrawn.map(\.rawValue).sorted().joined(separator: ", "))")
      }
    }
    #expect(checked > 0)
    #expect(missing.isEmpty, "controls with no drawing: \(missing)")
  }
}
