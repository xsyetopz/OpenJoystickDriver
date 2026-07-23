import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite(.serialized)
struct RemappingRPCTests {
  @Test func explicitPayloadsRoundTripWithoutAssociatedEnumAmbiguity() throws {
    let profile = makeProfile()
    let snapshot = makeSnapshot(profile: profile)
    let data = try JSONEncoder().encode(snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let routes = try #require(object["routes"] as? [[String: Any]])
    let route = try #require(routes.first)

    #expect(route["selection"] as? String == "remapping")
    #expect(route["eligibility"] as? String == "eligible")
    #expect(route["runtime_identifier"] as? String == "045e:028e:location:1")
    #expect(route["serial_number"] == nil)
    #expect(try JSONDecoder().decode(ApplicationServiceRemappingSnapshotPayload.self, from: data)
      == snapshot)
  }

  @Test func clientUsesEveryStableMethodAndDecodesTypedResults() async throws {
    let socketPath = temporarySocketPath()
    let profile = makeProfile()
    let snapshot = makeSnapshot(profile: profile)
    let methods = MethodRecorder()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        methods.append(request.method)
        do {
          let result: Data
          switch ApplicationServiceRemappingRPCMethod(rawValue: request.method) {
          case .getProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileIDArguments.self,
              from: request.arguments
            )
            #expect(arguments.profileID == profile.id)
            result = try JSONEncoder().encode(profile)
          case .getPostEventAccess, .requestPostEventAccess:
            result = try JSONEncoder().encode(RemappingPostEventAccessState.granted)
          case .createProfile, .importProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileArguments.self,
              from: request.arguments
            )
            #expect(arguments.profile == profile)
            result = try JSONEncoder().encode(snapshot)
          case .updateProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileUpdateArguments.self,
              from: request.arguments
            )
            #expect(arguments.profile == profile)
            #expect(arguments.expectedCurrent == profile)
            result = try JSONEncoder().encode(snapshot)
          case .deleteProfile, .activateProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileIDArguments.self,
              from: request.arguments
            )
            #expect(arguments.profileID == profile.id)
            result = try JSONEncoder().encode(snapshot)
          case .deactivateProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingModelArguments.self,
              from: request.arguments
            )
            #expect(arguments.vendorID == 1118)
            #expect(arguments.productID == 654)
            result = try JSONEncoder().encode(snapshot)
          case .getSnapshot:
            result = try JSONEncoder().encode(snapshot)
          case nil:
            throw ApplicationServiceClientError.invalidResponse
          }
          completion(LocalServiceRPCResponse(result: result, error: nil))
        } catch {
          completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
        }
      }
    )
    try server.start()
    defer { server.stop() }
    let client = ApplicationServiceClient(socketPath: socketPath)
    client.connect()
    #expect(client.isConnected)

    #expect(try await client.getRemappingSnapshot() == snapshot)
    #expect(try await client.getRemappingProfile(id: profile.id) == profile)
    #expect(try await client.createRemappingProfile(profile) == snapshot)
    #expect(try await client.updateRemappingProfile(profile, expectedCurrent: profile) == snapshot)
    #expect(try await client.importRemappingProfile(profile) == snapshot)
    #expect(try await client.deleteRemappingProfile(id: profile.id) == snapshot)
    #expect(try await client.activateRemappingProfile(id: profile.id) == snapshot)
    #expect(
      try await client.deactivateRemappingProfile(vendorID: 1118, productID: 654) == snapshot
    )
    #expect(try await client.getRemappingPostEventAccess() == .granted)
    #expect(try await client.requestRemappingPostEventAccess() == .granted)
    #expect(Set(methods.snapshot()) == Set(
      ApplicationServiceRemappingRPCMethod.allCases.map(\.rawValue)
    ))
  }

  @Test func clientReconstructsStableCodeBearingRemoteFailure() async throws {
    let socketPath = temporarySocketPath()
    let expected = ApplicationServiceRemappingRPCError(
      code: .profileUpdateConflict,
      message: "Profile changed since it was read."
    )
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _, completion in
        completion(LocalServiceRPCResponse(result: nil, error: expected.rpcDescription))
      }
    )
    try server.start()
    defer { server.stop() }
    let client = ApplicationServiceClient(socketPath: socketPath)
    client.connect()

    await #expect(throws: expected) {
      try await client.getRemappingProfile(id: UUID())
    }
  }

  @Test func argumentLimitLeavesRoomForTheBase64FramedEnvelope() throws {
    let arguments = Data(count: ApplicationServiceRemappingRPC.maximumArgumentBytes)
    let request = LocalServiceRPCRequest(method: "createRemappingProfile", arguments: arguments)
    let encodedRequest = try JSONEncoder().encode(request)
    let response = LocalServiceRPCResponse(result: arguments, error: nil)
    let encodedResponse = try JSONEncoder().encode(response)

    #expect(encodedRequest.count < LocalServiceRPCTransport.maximumFrameBytes)
    #expect(encodedResponse.count < LocalServiceRPCTransport.maximumFrameBytes)
    #expect(LocalServiceRPCTransport.maximumFrameBytes
      == ApplicationServiceRemappingRPC.maximumTransportFrameBytes)
    #expect(RemappingProfile.maximumEncodedBytes
      == ApplicationServiceRemappingRPC.maximumPayloadBytes)
  }

  @Test func updateArgumentsRoundTripExactlyAndFitArgumentBounds() throws {
    let expectedCurrent = maximumProfile(0)
    let updated = RemappingProfile(
      schemaVersion: expectedCurrent.schemaVersion,
      id: expectedCurrent.id,
      name: "Updated",
      device: expectedCurrent.device,
      applicationScope: expectedCurrent.applicationScope,
      bindings: expectedCurrent.bindings
    )
    let arguments = ApplicationServiceRemappingProfileUpdateArguments(
      profile: updated,
      expectedCurrent: expectedCurrent
    )

    let encoded = try JSONEncoder().encode(arguments)
    let decoded = try JSONDecoder().decode(
      ApplicationServiceRemappingProfileUpdateArguments.self,
      from: encoded
    )

    #expect(decoded.profile == updated)
    #expect(decoded.expectedCurrent == expectedCurrent)
    #expect(encoded.count <= ApplicationServiceRemappingRPC.maximumArgumentBytes)
    let framed = try JSONEncoder().encode(
      LocalServiceRPCRequest(method: "updateRemappingProfile", arguments: encoded)
    )
    #expect(framed.count < ApplicationServiceRemappingRPC.maximumTransportFrameBytes)
  }

  @Test func maximumValidLibraryShapeFitsPayloadAndOuterResponseBounds() throws {
    let profiles = (0..<RemappingPayloadLimits.maximumProfileCount).map(maximumProfile)
    for profile in profiles { try profile.validate() }
    let snapshot = ApplicationServiceRemappingSnapshotPayload(
      profiles: profiles,
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
    let result = try JSONEncoder().encode(snapshot)
    let framedResponse = try JSONEncoder().encode(
      LocalServiceRPCResponse(result: result, error: nil)
    )

    #expect(result.count <= ApplicationServiceRemappingRPC.maximumPayloadBytes)
    #expect(framedResponse.count < LocalServiceRPCTransport.maximumFrameBytes)
  }

  private func makeProfile() -> RemappingProfile {
    RemappingProfile(
      id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
      name: "Desktop",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: []
    )
  }

  private func maximumProfile(_ index: Int) -> RemappingProfile {
    let discreteDestination = RemappingDestination.keyboard(
      key: .keypadEqual,
      modifiers: Set(RemappingKeyModifier.allCases)
    )
    let turbo = RemappingTurbo(repeatRateHz: 60, dutyCycle: 0.95)
    var bindings = RemappingButton.allCases.map {
      RemappingBinding(source: .button($0), destination: discreteDestination, turbo: turbo)
    }
    bindings += RemappingDpadDirection.allCases.map {
      RemappingBinding(source: .dpad($0), destination: discreteDestination, turbo: turbo)
    }
    for axis in RemappingAxis.allCases {
      bindings.append(
        RemappingBinding(
          source: .axis(axis),
          destination: .mouseMovement(.x),
          axisTuning: .default
        )
      )
      for direction in [RemappingAxisDirection.negative, .positive] {
        bindings.append(
          RemappingBinding(
            source: .axisDirection(axis, direction),
            destination: discreteDestination,
            axisTuning: .default,
            turbo: turbo
          )
        )
      }
    }
    let suffix = String(format: "%03d", index)
    return RemappingProfile(
      name: String(repeating: "P", count: 77) + suffix,
      device: RemappingDeviceScope(vendorID: UInt16(index), productID: UInt16(index)),
      applicationScope: .application(
        bundleIdentifier: "com." + String(repeating: "a", count: 251)
      ),
      bindings: bindings
    )
  }

  private func makeSnapshot(
    profile: RemappingProfile
  ) -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: [profile],
      activeProfiles: [
        ApplicationServiceRemappingActiveProfilePayload(
          vendorID: 1118,
          productID: 654,
          profileID: profile.id,
          profileName: profile.name,
          applicationScope: profile.applicationScope
        ),
      ],
      routes: [
        ApplicationServiceRemappingRoutePayload(
          vendorID: 1118,
          productID: 654,
          runtimeIdentifier: "045e:028e:location:1",
          selection: .remapping,
          eligibility: .eligible,
          activeProfileID: profile.id,
          activeProfileName: profile.name,
          applicationScope: profile.applicationScope,
          frontmostBundleIdentifier: "com.example.Game",
          postEventAccess: .granted,
          failure: nil
        ),
      ],
      postEventAccess: .granted
    )
  }

  private func temporarySocketPath() -> String {
    "/tmp/com.openjoystickdriver.remapping.\(UUID().uuidString).rpc"
  }
}

private final class MethodRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var methods: [String] = []

  func append(_ method: String) {
    lock.withLock { methods.append(method) }
  }

  func snapshot() -> [String] {
    lock.withLock { methods }
  }
}
