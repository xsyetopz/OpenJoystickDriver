import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct AutomationServiceTests {
  /// A service that answers with fixed controllers and profiles.
  private struct FakeService: AutomationService {
    var devices: [ApplicationServiceDeviceDescription] = []
    var profiles: [RemappingProfile] = []
    var active: Set<UUID> = []

    func connectedDevices() -> [ApplicationServiceDeviceDescription] { devices }

    func getRemappingSnapshot() throws -> ApplicationServiceRemappingSnapshotPayload {
      snapshot(active: active)
    }

    /// The snapshot after activation, as the service returns it; the fake keeps no state.
    func activateRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
      snapshot(active: active.union([id]))
    }

    func deactivateRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
      snapshot(active: active.subtracting([id]))
    }

    private func snapshot(active: Set<UUID>) -> ApplicationServiceRemappingSnapshotPayload {
      ApplicationServiceRemappingSnapshotPayload(
        profiles: profiles,
        activeProfiles: profiles.filter { active.contains($0.id) }.map {
          ApplicationServiceRemappingActiveProfilePayload(
            vendorID: $0.device.vendorID,
            productID: $0.device.productID,
            profileID: $0.id,
            profileName: $0.name,
            applicationScope: $0.applicationScope
          )
        },
        routes: [],
        postEventAccess: .granted
      )
    }
  }

  private struct SnapshotUnavailable: Error {}

  /// A service whose profile library cannot be read.
  private struct FailingService: AutomationService {
    func connectedDevices() -> [ApplicationServiceDeviceDescription] { [] }

    func getRemappingSnapshot() throws -> ApplicationServiceRemappingSnapshotPayload {
      throw SnapshotUnavailable()
    }

    func activateRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
      throw SnapshotUnavailable()
    }

    func deactivateRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
      throw SnapshotUnavailable()
    }
  }

  private static func device(
    _ name: String,
    runtimeID: String,
    unitID: String?,
    productID: UInt16 = 0x028E,
    battery: BatteryLevel = .unknown
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: 0x045E,
      productID: productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      connectionState: ControllerConnectionState(
        transport: .usb,
        backend: .usbDriverKit,
        isConnected: true,
        power: ControllerConnectionState.Power(
          charging: .discharging,
          battery: battery,
          wiredPower: nil
        )
      ),
      runtimeIdentifier: runtimeID,
      unitIdentifier: unitID
    )
  }

  private static func profile(_ name: String) -> RemappingProfile {
    RemappingProfile(
      id: UUID(),
      name: name,
      device: RemappingDeviceScope(vendorID: 0x054C, productID: 0x0CE6),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: []
    )
  }

  @Test
  func controllersUseTheUnitIDAndFallBackToTheRuntimeID() async {
    let service = FakeService(devices: [
      Self.device("Pad A", runtimeID: "pad-1", unitID: "U-1"),
      Self.device("Pad B", runtimeID: "pad-2", unitID: nil),
    ])

    let controllers = await service.controllers()

    #expect(controllers.map(\.id) == ["U-1", "pad-2", "045E:028E"])
    #expect(controllers.map(\.name) == ["Pad A", "Pad B", "Pad A"])
    #expect(controllers.map(\.model) == ["045E:028E", "045E:028E", "045E:028E"])
    #expect(controllers.map(\.isModelMatch) == [false, false, true])
  }

  @Test
  func controllersReportTheBatteryChargeAsTheDeviceReportsIt() async throws {
    let service = FakeService(devices: [
      Self.device(
        "Pad A",
        runtimeID: "pad-1",
        unitID: nil,
        battery: BatteryLevel(percentage: 30...39)
      ),
      Self.device("Pad B", runtimeID: "pad-2", unitID: nil, productID: 0x0B12),
    ])

    #expect(await service.controllers().map(\.battery) == [30...39, nil, 30...39, nil])
    #expect(try await service.controllers(ids: ["045E:028E"]).map(\.battery) == [30...39])
  }

  @Test
  func suggestionsListEachConnectedModelOnceInConnectionOrder() async {
    let service = FakeService(devices: [
      Self.device("Pad A", runtimeID: "pad-1", unitID: nil, productID: 0x0B12),
      Self.device("Pad B", runtimeID: "pad-2", unitID: nil),
      Self.device("Pad C", runtimeID: "pad-3", unitID: nil, productID: 0x0B12),
    ])

    let models = await service.controllers().filter(\.isModelMatch)

    #expect(models.map(\.id) == ["045E:0B12", "045E:028E"])
  }

  @Test
  func aModelIDResolvesToTheOneConnectedControllerOfThatModel() async throws {
    let service = FakeService(devices: [
      Self.device("Pad A", runtimeID: "pad-1", unitID: "U-1"),
      Self.device("Pad B", runtimeID: "pad-2", unitID: nil, productID: 0x0B12),
    ])

    let controllers = try await service.controllers(ids: ["045e:0b12", "1234:5678"])

    #expect(controllers.map(\.id) == ["045e:0b12"])
    #expect(controllers.map(\.name) == ["Pad B"])
    #expect(controllers.map(\.model) == ["045E:0B12"])
    #expect(controllers.map(\.isModelMatch) == [true])
  }

  @Test
  func aModelIDThatMatchesSeveralControllersThrows() async {
    let service = FakeService(devices: [
      Self.device("Pad A", runtimeID: "pad-1", unitID: "U-1"),
      Self.device("Pad B", runtimeID: "pad-2", unitID: nil),
    ])

    await #expect(
      throws: AutomationAmbiguousModelError(
        model: "045E:028E",
        controllers: service.controllers().filter { !$0.isModelMatch }
      )
    ) { try await service.controllers(ids: ["045E:028E"]) }
  }

  @Test
  func controllerIDsResolveByUnitOrRuntimeIDInRequestOrder() async throws {
    let service = FakeService(devices: [
      Self.device("Pad A", runtimeID: "pad-1", unitID: "U-1"),
      Self.device("Pad B", runtimeID: "pad-2", unitID: nil),
    ])

    let controllers = try await service.controllers(ids: ["pad-2", "missing", "pad-1"])

    #expect(controllers.map(\.id) == ["pad-2", "U-1"])
  }

  @Test
  func profilesReportTheirModelAndWhetherTheyAreActive() async throws {
    let racing = Self.profile("Racing")
    let menus = Self.profile("Menus")
    let service = FakeService(profiles: [racing, menus], active: [menus.id])

    let profiles = try await service.profiles()

    #expect(profiles.map(\.id) == [racing.id, menus.id])
    #expect(profiles.map(\.name) == ["Racing", "Menus"])
    #expect(profiles.map(\.isActive) == [false, true])
    #expect(profiles.map(\.model) == ["054C:0CE6", "054C:0CE6"])
  }

  @Test
  func profileIDsResolveInRequestOrderAndSkipUnknownIDs() async throws {
    let racing = Self.profile("Racing")
    let menus = Self.profile("Menus")
    let service = FakeService(profiles: [racing, menus])

    let profiles = try await service.profiles(ids: [menus.id, UUID(), racing.id])

    #expect(profiles.map(\.id) == [menus.id, racing.id])
  }

  @Test
  func profileQueriesPassOnASnapshotError() async {
    await #expect(throws: SnapshotUnavailable.self) { try await FailingService().profiles() }
    await #expect(throws: SnapshotUnavailable.self) {
      try await FailingService().profiles(ids: [UUID()])
    }
  }

  @Test
  func activatingAndDeactivatingReturnTheProfileInItsNewState() async throws {
    let racing = Self.profile("Racing")
    let service = FakeService(profiles: [racing])

    let activated = try await service.activateProfile(id: racing.id)
    let deactivated = try await FakeService(profiles: [racing], active: [racing.id])
      .deactivateProfile(id: racing.id)

    #expect(activated.id == racing.id)
    #expect(activated.isActive)
    #expect(!deactivated.isActive)
  }

  @Test
  func activatingAProfileMissingFromTheResultThrowsNotFound() async {
    let missing = UUID()

    await #expect(throws: RemappingProfileLibraryError.profileNotFound(missing)) {
      try await FakeService().activateProfile(id: missing)
    }
    await #expect(throws: SnapshotUnavailable.self) {
      try await FailingService().deactivateProfile(id: missing)
    }
  }
}
