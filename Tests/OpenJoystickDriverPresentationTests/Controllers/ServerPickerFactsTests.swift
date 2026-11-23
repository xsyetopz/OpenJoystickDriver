import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// The Handled by picker names who serves a controller, so the general facts leave out the rows
/// that only repeat its selection.
struct ServerPickerFactsTests {
  private func device(
    observation: ControllerOwnershipObservation,
    accessRoute: ControllerAccessRoute,
    publication: ApplicationServicePublicationStatus?
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "PLAYSTATION(R)3 Controller",
      vendorID: 0x054C,
      productID: 0x0268,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: observation,
      hidInputOwnership: .shared,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: accessRoute,
      sessionToken: .fixture("picker-device")
    )
    device.publication = publication
    return device
  }

  private func kinds(_ device: ApplicationServiceDeviceDescription) -> [ControllerFact.Kind] {
    ControllerDetailFacts.general(for: device).map(\.kind)
  }

  @Test
  func pickerReplacesRouteAndSystemPublication() {
    let served = device(
      observation: .systemGamepad,
      accessRoute: .system,
      publication: .notPublished(.systemGamepad)
    )
    #expect(ServingPolicy.offersServerChoice(ServingInput(served)))
    #expect(!kinds(served).contains(.serving))
    #expect(!kinds(served).contains(.publication))
  }

  @Test
  func pickerKeepsPublicationWithOtherReason() {
    let waiting = device(
      observation: .systemGamepad,
      accessRoute: .system,
      publication: .notPublished(.sessionSuspended)
    )
    #expect(kinds(waiting).contains(.publication))
    #expect(!kinds(waiting).contains(.serving))
  }

  @Test
  func noPickerKeepsRouteAndPublication() {
    let raw = device(
      observation: .exclusiveRawUSB,
      accessRoute: .rawAccess,
      publication: .notPublished(.systemGamepad)
    )
    #expect(!ServingPolicy.offersServerChoice(ServingInput(raw)))
    #expect(kinds(raw).contains(.serving))
    #expect(kinds(raw).contains(.publication))
  }
}
