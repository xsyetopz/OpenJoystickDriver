import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ConnectedControllerSelectionTests {
  @Test func selectsTheOnlyMatchingModelWithoutAnExplicitRuntimeIdentifier() throws {
    let other = device(name: "Other", vendorID: 3, productID: 4, id: "other")
    let expected = device(name: "Expected", vendorID: 1, productID: 2, id: "expected")

    let selected = try ConnectedControllerSelection.resolve(
      devices: [other, expected],
      vendorID: 1,
      productID: 2
    )

    #expect(selected.runtimeIdentifier == "expected")
  }

  @Test func selectsOneOfTwoIdenticalModelsByRuntimeIdentifier() throws {
    let first = device(name: "Controller", vendorID: 1, productID: 2, id: "first")
    let second = device(name: "Controller", vendorID: 1, productID: 2, id: "second")

    let selected = try ConnectedControllerSelection.resolve(
      devices: [first, second],
      vendorID: 1,
      productID: 2,
      runtimeIdentifier: "second"
    )

    #expect(selected.runtimeIdentifier == "second")
  }

  @Test func rejectsAmbiguousModelsAndListsTheirOpaqueSelectors() {
    let first = device(name: "Controller", vendorID: 1, productID: 2, id: "first")
    let second = device(name: "Controller", vendorID: 1, productID: 2, id: "second")

    #expect(throws: ConnectedControllerSelection.Failure.self) {
      try ConnectedControllerSelection.resolve(
        devices: [first, second],
        vendorID: 1,
        productID: 2
      )
    }

    do {
      _ = try ConnectedControllerSelection.resolve(
        devices: [first, second],
        vendorID: 1,
        productID: 2
      )
      Issue.record("Expected ambiguous selection to fail")
    } catch {
      #expect(error.localizedDescription.contains("--device first"))
      #expect(error.localizedDescription.contains("--device second"))
    }
  }

  @Test func runtimeIdentifierMustBelongToTheRequestedModel() {
    let selectedIDOnAnotherModel = device(
      name: "Other",
      vendorID: 3,
      productID: 4,
      id: "selected"
    )

    #expect(throws: ConnectedControllerSelection.Failure.self) {
      try ConnectedControllerSelection.resolve(
        devices: [selectedIDOnAnotherModel],
        vendorID: 1,
        productID: 2,
        runtimeIdentifier: "selected"
      )
    }
  }

  @Test func rejectsAnOpaqueSelectorSharedByMultipleCandidates() {
    let first = device(name: "First", vendorID: 1, productID: 2, id: "duplicate")
    let second = device(name: "Second", vendorID: 1, productID: 2, id: "duplicate")

    #expect(throws: ConnectedControllerSelection.Failure.self) {
      try ConnectedControllerSelection.resolve(
        devices: [first, second],
        runtimeIdentifier: "duplicate"
      )
    }
  }

  private func device(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    id: String
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: vendorID,
      productID: productID,
      parser: "Generic HID",
      connection: "HID",
      serialNumber: nil,
      runtimeIdentifier: id
    )
  }
}
