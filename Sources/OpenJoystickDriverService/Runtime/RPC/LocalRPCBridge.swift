import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Decodes `request`, awaits its handler, and encodes the value or error as the response.
  func handleLocalRPC(_ request: LocalServiceRPCRequest) async -> LocalServiceRPCResponse {
    do { return try await response(to: request) } catch let error
      as ApplicationServiceRemappingRPCError
    { return LocalServiceRPCResponse(remappingError: error) } catch {
      return LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
    }
  }

  private func response(to request: LocalServiceRPCRequest) async throws -> LocalServiceRPCResponse
  {
    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
      try JSONDecoder().decode(type, from: request.arguments)
    }
    func send<Value: Encodable>(_ value: Value) throws -> LocalServiceRPCResponse {
      LocalServiceRPCResponse(result: try JSONEncoder().encode(value), error: nil)
    }
    func decodeRemapping<Value: Decodable>(_ type: Value.Type) throws -> Value {
      guard request.arguments.count <= ApplicationServiceRemappingRPC.maximumArgumentBytes else {
        throw ApplicationServiceRemappingRPCError(
          code: .argumentTooLarge,
          message: "Remapping RPC arguments exceed the service limit."
        )
      }
      do { return try decode(type) } catch let error as ApplicationServiceRemappingRPCError {
        throw error
      } catch {
        throw ApplicationServiceRemappingRPCError(
          code: .invalidArguments,
          message: "Remapping RPC arguments are malformed."
        )
      }
    }
    func sendRemapping<Value: Encodable>(_ value: Value) throws -> LocalServiceRPCResponse {
      do {
        let encodedValue = try JSONEncoder().encode(value)
        guard encodedValue.count <= ApplicationServiceRemappingRPC.maximumPayloadBytes else {
          throw ApplicationServiceRemappingRPCError(
            code: .responseTooLarge,
            message: "The remapping RPC response exceeds the service limit."
          )
        }
        let response = LocalServiceRPCResponse(result: encodedValue, error: nil)
        guard
          try JSONEncoder().encode(response).count
            <= ApplicationServiceRemappingRPC.maximumTransportFrameBytes
        else {
          throw ApplicationServiceRemappingRPCError(
            code: .responseTooLarge,
            message: "The remapping RPC response exceeds the transport frame limit."
          )
        }
        return response
      } catch let error as ApplicationServiceRemappingRPCError { throw error } catch {
        throw ApplicationServiceRemappingRPCError(
          code: .responseEncodingFailed,
          message: "The remapping RPC response could not be encoded."
        )
      }
    }

    guard let method = ApplicationServiceRPCMethod(rawValue: request.method) else {
      throw NSError(
        domain: "OpenJoystickDriver.LocalServiceRPC",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Unknown RPC method: \(request.method)"]
      )
    }
    switch method {
    case .getStatus:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(await getStatus())
    case .requestRequiredAccess:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(await requestRequiredAccess())
    case .requestAccess:
      let value = try decode(LocalServiceRPCPermissionArguments.self)
      return try send(await requestAccess(value.requirement))
    case .getControllerState:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await getControllerState(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .getVirtualOutputState:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await getVirtualOutputState(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .getPacketLog:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await getPacketLog(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .sendControllerOutput:
      let value = try decode(LocalServiceRPCControllerOutputArguments.self)
      return try send(
        await sendControllerOutput(
          value.command,
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .previewPhysicalColor:
      let value = try decode(LocalServiceRPCColorPreviewArguments.self)
      return try send(
        await previewPhysicalColor(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          token: value.token,
          red: value.red,
          green: value.green,
          blue: value.blue
        )
      )
    case .releasePhysicalColorPreview:
      let value = try decode(LocalServiceRPCColorPreviewReleaseArguments.self)
      return try send(
        await releasePhysicalColorPreview(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          token: value.token
        )
      )
    case .setSuppressOutput:
      return try send(await setSuppressOutput(try decode(LocalServiceRPCBoolArguments.self).value))
    case .getVirtualDeviceDiagnostics:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(getVirtualDeviceDiagnostics())
    case .setVirtualHIDProfileOverride:
      let value = try decode(LocalServiceRPCVirtualHIDProfileOverrideArguments.self)
      return try send(
        await setVirtualHIDProfileOverride(
          value.profile,
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .resetVirtualHIDProfileOverride:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await resetVirtualHIDProfileOverride(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .suspendController:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await suspendController(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .resumeController:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await resumeController(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .disconnectWirelessController:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await disconnectWirelessController(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier
        )
      )
    case .resetSettings:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(await resetSettings())
    case .getSettings:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(getSettings())
    case .setSetting:
      let value = try decode(ApplicationServiceSettingArguments.self)
      return try send(try setSetting(value.key, to: value.value))
    case .remappingMotionCalibration:
      let value = try decodeRemapping(ApplicationServiceMotionCalibrationArguments.self)
      return try sendRemapping(try await remappingMotionCalibration(value))
    case .pairRemappingJoyCons:
      let value = try decodeRemapping(ApplicationServiceJoyConPairArguments.self)
      return try sendRemapping(try await pairRemappingJoyCons(value))
    case .unpairRemappingJoyCons:
      let value = try decodeRemapping(ApplicationServiceJoyConUnpairArguments.self)
      return try sendRemapping(try await unpairRemappingJoyCons(value))
    case .getRemappingSnapshot:
      _ = try decodeRemapping(LocalServiceRPCEmptyArguments.self)
      return try sendRemapping(try await getRemappingSnapshot())
    case .getRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
      return try sendRemapping(try await getRemappingProfile(id: value.profileID))
    case .createRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileArguments.self)
      return try sendRemapping(try await createRemappingProfile(value.profile))
    case .updateRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileUpdateArguments.self)
      return try sendRemapping(
        try await updateRemappingProfile(value.profile, expectedCurrent: value.expectedCurrent)
      )
    case .deleteRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
      return try sendRemapping(try await deleteRemappingProfile(id: value.profileID))
    case .deleteDamagedRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileIssueArguments.self)
      return try sendRemapping(try await deleteDamagedRemappingProfile(value))
    case .resetRemappingProfileLibrary:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileIssueArguments.self)
      return try sendRemapping(try await resetRemappingProfileLibrary(value))
    case .importRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileArguments.self)
      return try sendRemapping(try await importRemappingProfile(value.profile))
    case .activateRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
      return try sendRemapping(try await activateRemappingProfile(id: value.profileID))
    case .deactivateRemappingProfile:
      let value = try decodeRemapping(ApplicationServiceRemappingModelArguments.self)
      return try sendRemapping(
        try await deactivateRemappingProfile(vendorID: value.vendorID, productID: value.productID)
      )
    case .deactivateRemappingProfileByID:
      let value = try decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
      return try sendRemapping(try await deactivateRemappingProfile(id: value.profileID))
    case .getRemappingPostEventAccess:
      _ = try decodeRemapping(LocalServiceRPCEmptyArguments.self)
      return try sendRemapping(try await getRemappingPostEventAccess())
    case .requestRemappingPostEventAccess:
      _ = try decodeRemapping(LocalServiceRPCEmptyArguments.self)
      return try sendRemapping(try await requestRemappingPostEventAccess())
    }
  }
}
