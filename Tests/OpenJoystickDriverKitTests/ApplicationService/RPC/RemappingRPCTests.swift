import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite(.serialized, .removingTemporarySockets)
struct RemappingRPCTests {
  @Test
  func explicitPayloadsRoundTripWithoutAssociatedEnumAmbiguity() throws {
    let profile = makeProfile()
    let snapshot = makeSnapshot(profile: profile)
    let data = try JSONEncoder().encode(snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let routes = try #require(object["routes"] as? [[String: Any]])
    let route = try #require(routes.first)

    #expect(route["selection"] as? String == "remapping")
    #expect(route["eligibility"] as? String == "eligible")
    #expect(route["sessionToken"] as? String == ControllerSessionToken.fixture("pad-1").rawValue)
    #expect(route["serialNumber"] == nil)
    #expect(
      try JSONDecoder().decode(ApplicationServiceRemappingSnapshotPayload.self, from: data)
        == snapshot
    )
  }

  /// A profile that fails to decode in a request gets the invalid-profile code, the same code the
  /// store gives the same document.
  @Test
  func aRequestWithAnInvalidProfileFailsWithTheInvalidProfileCode() throws {
    let version = OpenJoystickDriverAPI.version
    let document = #"{"apiVersion":"\#(version)","kind":"Profile","name":"Pad"}"#
    let request = Data(#"{"profile":\#(document)}"#.utf8)
    let update = Data(#"{"profile":\#(document),"expectedCurrent":\#(document)}"#.utf8)

    for decode in [
      {
        _ = try JSONDecoder().decode(
          ApplicationServiceRemappingProfileArguments.self,
          from: request
        )
      },
      {
        _ = try JSONDecoder().decode(
          ApplicationServiceRemappingProfileUpdateArguments.self,
          from: update
        )
      },
    ] {
      do {
        try decode()
        Issue.record("The invalid profile decoded.")
      } catch let error as ApplicationServiceRemappingRPCError {
        #expect(error.code.errorCode == .invalidProfile)
      }
    }
    do {
      _ = try RemappingProfileFileStore.load(from: PropertyListFixture.bytes(json: document))
    } catch {
      #expect(RemappingProfileFileStore.problemCode(error) == .invalidProfile)
    }
  }

  /// A profile with a missing or unsupported `apiVersion` gets the unsupported-version code in a
  /// request, the same code the store gives the same document.
  @Test
  func aRequestWithAnUnsupportedAPIVersionFailsWithTheUnsupportedAPIVersionCode() throws {
    let documents = [
      #"{"kind":"Profile","name":"Pad"}"#,
      #"{"apiVersion":"ojd/v0","kind":"Profile","name":"Pad"}"#,
    ]
    for document in documents {
      let request = Data(#"{"profile":\#(document)}"#.utf8)
      let update = Data(#"{"profile":\#(document),"expectedCurrent":\#(document)}"#.utf8)
      do {
        _ = try JSONDecoder().decode(
          ApplicationServiceRemappingProfileArguments.self,
          from: request
        )
        Issue.record("The profile decoded.")
      } catch let error as ApplicationServiceRemappingRPCError {
        #expect(error.code == .unsupportedAPIVersion)
        #expect(error.code.errorCode == .unsupportedAPIVersion)
      }
      do {
        _ = try JSONDecoder().decode(
          ApplicationServiceRemappingProfileUpdateArguments.self,
          from: update
        )
        Issue.record("The profile decoded.")
      } catch let error as ApplicationServiceRemappingRPCError {
        #expect(error.code.errorCode == .unsupportedAPIVersion)
      }
      do {
        _ = try RemappingProfileFileStore.load(from: PropertyListFixture.bytes(json: document))
      } catch {
        #expect(RemappingProfileFileStore.problemCode(error) == .unsupportedAPIVersion)
      }
    }
  }

  @Test
  func aProfileIssueWithoutAKindFailsToDecode() {
    let id = UUID().uuidString
    let issue = Data(#"{"id":"\#(id)","code":"E3008","message":"m"}"#.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(ApplicationServiceRemappingProfileIssue.self, from: issue)
    }
  }

  @Test
  func routingActiveProfilePrefersGlobalScopeForSharedModel() {
    func entry(
      _ name: String,
      _ scope: RemappingApplicationScope,
      productID: UInt16 = 2
    ) -> ApplicationServiceRemappingActiveProfilePayload {
      ApplicationServiceRemappingActiveProfilePayload(
        vendorID: 1,
        productID: productID,
        profileID: UUID(),
        profileName: name,
        applicationScope: scope
      )
    }
    let active = [
      entry("Global", .global), entry("Game", .application(appIDs: ["com.example.game"])),
      entry("Other", .global, productID: 3),
    ]

    #expect(active.routingActiveProfile(vendorID: 1, productID: 2)?.profileName == "Global")
    #expect(active.routingActiveProfile(vendorID: 1, productID: 3)?.profileName == "Other")
    #expect(active.routingActiveProfile(vendorID: 1, productID: 4) == nil)
    #expect(
      Array(active.prefix(2).suffix(1)).routingActiveProfile(vendorID: 1, productID: 2)?.profileName
        == "Game"
    )
  }

  @Test
  func clientUsesEveryStableMethodAndDecodesTypedResults() async throws {
    let socketPath = temporarySocketPath()
    let profile = makeProfile()
    let snapshot = makeSnapshot(profile: profile)
    let methods = MethodRecorder()
    let calibration = RemappingMotionCalibrationStatus(
      hasMotionBaseline: true,
      isCollecting: true,
      offsetDegreesPerSecond: ControllerMotionVector(x: 1, y: 2, z: 3)
    )
    let pairSessionID = UUID()
    let issueID = UUID()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        methods.append(request.method)
        do {
          let result: Data
          switch ApplicationServiceRPCMethod(rawValue: request.method) {
          case .remappingMotionCalibration:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceMotionCalibrationArguments.self,
              from: request.arguments
            )
            #expect(arguments.controller == .session(.fixture("pad-1")))
            #expect(arguments.command == .start)
            result = try JSONEncoder().encode(calibration)
          case .pairRemappingJoyCons:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceJoyConPairArguments.self,
              from: request.arguments
            )
            #expect(arguments.left == .session(.fixture("left")))
            #expect(arguments.right == .session(.fixture("right")))
            #expect(arguments.profileID == profile.id)
            result = try JSONEncoder().encode(snapshot)
          case .unpairRemappingJoyCons:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceJoyConUnpairArguments.self,
              from: request.arguments
            )
            #expect(arguments.sessionID == pairSessionID)
            result = try JSONEncoder().encode(snapshot)
          case .getRemappingProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileIDArguments.self,
              from: request.arguments
            )
            #expect(arguments.profileID == profile.id)
            result = try JSONEncoder().encode(profile)
          case .getRemappingPostEventAccess, .requestRemappingPostEventAccess:
            result = try JSONEncoder().encode(RemappingPostEventAccessState.granted)
          case .createRemappingProfile, .importRemappingProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileArguments.self,
              from: request.arguments
            )
            #expect(arguments.profile == profile)
            result = try JSONEncoder().encode(snapshot)
          case .updateRemappingProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileUpdateArguments.self,
              from: request.arguments
            )
            #expect(arguments.profile == profile)
            #expect(arguments.expectedCurrent == profile)
            result = try JSONEncoder().encode(snapshot)
          case .deleteRemappingProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileIDArguments.self,
              from: request.arguments
            )
            #expect(arguments.profileID == profile.id)
            result = try JSONEncoder().encode(snapshot)
          case .activateRemappingProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingActivateArguments.self,
              from: request.arguments
            )
            #expect(arguments.profileID == profile.id)
            #expect(arguments.allowEmpty)
            result = try JSONEncoder().encode(snapshot)
          case .deleteDamagedRemappingProfile, .resetRemappingProfileLibrary:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileIssueArguments.self,
              from: request.arguments
            )
            #expect(arguments.issueID == issueID)
            result = try JSONEncoder().encode(snapshot)
          case .deactivateRemappingProfile:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingModelArguments.self,
              from: request.arguments
            )
            #expect(arguments.vendorID == 1118)
            #expect(arguments.productID == 654)
            result = try JSONEncoder().encode(snapshot)
          case .deactivateRemappingProfileByID:
            let arguments = try JSONDecoder().decode(
              ApplicationServiceRemappingProfileIDArguments.self,
              from: request.arguments
            )
            #expect(arguments.profileID == profile.id)
            result = try JSONEncoder().encode(snapshot)
          case .getRemappingSnapshot: result = try JSONEncoder().encode(snapshot)
          default: throw ApplicationServiceClientError.invalidResponse
          }
          return LocalServiceRPCResponse(result: result, error: nil)
        } catch {
          return LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
        }
      }
    )
    try server.start()
    defer { server.stop() }
    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect()
    #expect(client.isConnected)

    #expect(try await client.getRemappingSnapshot() == snapshot)
    #expect(try await client.getRemappingProfile(id: profile.id) == profile)
    #expect(try await client.createRemappingProfile(profile) == snapshot)
    #expect(try await client.updateRemappingProfile(profile, expectedCurrent: profile) == snapshot)
    #expect(try await client.importRemappingProfile(profile) == snapshot)
    #expect(try await client.deleteRemappingProfile(id: profile.id) == snapshot)
    #expect(try await client.deleteDamagedRemappingProfile(issueID: issueID) == snapshot)
    #expect(try await client.resetRemappingProfileLibrary(issueID: issueID) == snapshot)
    #expect(try await client.activateRemappingProfile(id: profile.id, allowEmpty: true) == snapshot)
    #expect(try await client.deactivateRemappingProfile(vendorID: 1118, productID: 654) == snapshot)
    #expect(try await client.deactivateRemappingProfile(profileID: profile.id) == snapshot)
    #expect(try await client.getRemappingPostEventAccess() == .granted)
    #expect(try await client.requestRemappingPostEventAccess() == .granted)
    #expect(
      try await client.remappingMotionCalibration(
        for: .session(.fixture("pad-1")),
        command: .start
      ) == calibration
    )
    #expect(
      try await client.pairRemappingJoyCons(
        left: .session(.fixture("left")),
        right: .session(.fixture("right")),
        profileID: profile.id
      ) == snapshot
    )
    #expect(try await client.unpairRemappingJoyCons(sessionID: pairSessionID) == snapshot)
    let remappingMethods = ApplicationServiceRPCMethod.allCases.map(\.rawValue).filter {
      $0.localizedCaseInsensitiveContains("remapping")
    }
    #expect(Set(methods.snapshot()) == Set(remappingMethods))
  }

  @Test
  func clientReconstructsStableCodeBearingRemoteFailure() async throws {
    let socketPath = temporarySocketPath()
    let expected = ApplicationServiceRemappingRPCError(
      code: .profileUpdateConflict,
      message: "Profile changed since it was read."
    )
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _ in
        return LocalServiceRPCResponse(remappingError: expected)
      }
    )
    try server.start()
    defer { server.stop() }
    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect()

    await #expect(throws: expected) { try await client.getRemappingProfile(id: UUID()) }
  }

  @Test
  func argumentLimitLeavesRoomForTheBase64FramedEnvelope() throws {
    let arguments = Data(count: ApplicationServiceRemappingRPC.maximumArgumentBytes)
    let request = LocalServiceRPCRequest(method: "createRemappingProfile", arguments: arguments)
    let encodedRequest = try JSONEncoder().encode(request)
    let response = LocalServiceRPCResponse(result: arguments, error: nil)
    let encodedResponse = try JSONEncoder().encode(response)

    #expect(encodedRequest.count < LocalServiceRPCTransport.maximumFrameBytes)
    #expect(encodedResponse.count < LocalServiceRPCTransport.maximumFrameBytes)
    #expect(
      LocalServiceRPCTransport.maximumFrameBytes
        == ApplicationServiceRemappingRPC.maximumTransportFrameBytes
    )
    #expect(
      RemappingProfile.maximumEncodedBytes == ApplicationServiceRemappingRPC.maximumPayloadBytes
    )
  }

  @Test
  func updateArgumentsRoundTripExactlyAndFitArgumentBounds() throws {
    let expectedCurrent = maximumProfile(0)
    let updated = RemappingProfile(
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

  @Test
  func maximumValidLibraryShapeFitsPayloadAndOuterResponseBounds() throws {
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
      touchMappings: [RemappingTouchMapping(surface: .primary, mode: .pointer)],
      bindings: [
        RemappingBinding(source: .touchContact(.primary), destination: .mouseButton(.left))
      ]
    )
  }

  private func maximumProfile(_ index: Int) -> RemappingProfile {
    let discreteDestination = RemappingDestination.keyboard(
      key: .keypadEqual,
      modifiers: Set(RemappingKeyModifier.allCases)
    )
    let turbo = RemappingTurbo(repeatRateHz: 60, dutyCycle: 0.95)
    var bindings = Control.allCases.map {
      RemappingBinding(source: .button($0), destination: discreteDestination, turbo: turbo)
    }
    bindings += RemappingDpadDirection.allCases.map {
      RemappingBinding(source: .dpad($0), destination: discreteDestination, turbo: turbo)
    }
    for axis in RemappingAxis.allCases {
      bindings.append(
        RemappingBinding(source: .axis(axis), destination: .mouseMovement(.x), axisTuning: .default)
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
    let suffix = unsafe String(format: "%03d", index)
    return RemappingProfile(
      name: String(repeating: "P", count: 77) + suffix,
      device: RemappingDeviceScope(vendorID: UInt16(index), productID: UInt16(index)),
      applicationScope: .application(appIDs: ["com." + String(repeating: "a", count: 251)]),
      bindings: bindings
    )
  }

  private func makeSnapshot(profile: RemappingProfile) -> ApplicationServiceRemappingSnapshotPayload
  {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: [profile],
      activeProfiles: [
        ApplicationServiceRemappingActiveProfilePayload(
          vendorID: 1118,
          productID: 654,
          profileID: profile.id,
          profileName: profile.name,
          applicationScope: profile.applicationScope
        )
      ],
      routes: [
        ApplicationServiceRemappingRoutePayload(
          vendorID: 1118,
          productID: 654,
          sessionToken: .fixture("pad-1"),
          selection: .remapping,
          eligibility: .eligible,
          activeProfileID: profile.id,
          activeProfileName: profile.name,
          applicationScope: profile.applicationScope,
          frontmostAppID: "com.example.Game",
          postEventAccess: .granted,
          failure: nil
        )
      ],
      postEventAccess: .granted
    )
  }
}

private final class MethodRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var methods: [String] = []

  func append(_ method: String) { lock.withLock { methods.append(method) } }

  func snapshot() -> [String] { lock.withLock { methods } }
}
