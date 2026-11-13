import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerReferenceResolutionTests {
  private let first = ConnectedController(
    logicalControllerID: LogicalControllerID(vendorID: 1, productID: 2, locationID: 1),
    sessionToken: .fixture("first"),
    installationKey: testPortKeyInstallationKey
  )
  private let second = ConnectedController(
    logicalControllerID: LogicalControllerID(vendorID: 1, productID: 2, locationID: 2),
    sessionToken: .fixture("second"),
    installationKey: testPortKeyInstallationKey
  )
  private let other = ConnectedController(
    logicalControllerID: LogicalControllerID(vendorID: 3, productID: 4, locationID: 3),
    sessionToken: .fixture("other"),
    installationKey: testPortKeyInstallationKey
  )

  private var connected: [ConnectedController] { [first, second, other] }

  @Test
  func sessionTokenOrPortKeyResolvesToItsControllerAmongIdenticalModels() throws {
    for controller in [first, second] {
      let session = ControllerReference.session(controller.sessionToken)
      #expect(try session.resolve(in: connected) == controller)
      let portKey = try #require(controller.portKey)
      #expect(try ControllerReference.port(portKey).resolve(in: connected) == controller)
    }
  }

  @Test
  func modelResolvesWhenOneConnectedControllerHasIt() throws {
    #expect(try ControllerReference.model(other.model).resolve(in: connected) == other)
  }

  @Test
  func modelSharedBySeveralControllersReportsEveryMatch() {
    let reference = ControllerReference.model(first.model)
    let ambiguous = ControllerReferenceError.ambiguous(
      reference,
      matches: [first.sessionToken, second.sessionToken]
    )
    #expect(throws: ambiguous) { try reference.resolve(in: connected) }
    #expect(ambiguous.errorCode == .notFound)
  }

  @Test
  func referenceToNoConnectedControllerIsNotFound() {
    let references: [ControllerReference] = [
      .session(.fixture("gone")),
      .port(.fixture("gone")),
      .model(ControllerModelID(vendorID: 9, productID: 9)),
    ]
    for reference in references {
      #expect(throws: ControllerReferenceError.notFound(reference)) {
        try reference.resolve(in: connected)
      }
    }
  }
}
