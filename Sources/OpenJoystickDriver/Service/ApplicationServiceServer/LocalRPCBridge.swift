import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  func handleLocalRPC(
    _ request: LocalServiceRPCRequest,
    completion: @escaping LocalServiceRPCServer.Completion
  ) {
    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
      try JSONDecoder().decode(type, from: request.arguments)
    }
    func send<Value: Encodable>(_ value: Value) {
      do {
        completion(
          LocalServiceRPCResponse(result: try JSONEncoder().encode(value), error: nil)
        )
      } catch {
        completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
      }
    }
    func fail(_ error: Error) {
      let description = (error as? ApplicationServiceRemappingRPCError)?.rpcDescription
        ?? error.localizedDescription
      completion(LocalServiceRPCResponse(result: nil, error: description))
    }
    func decodeRemapping<Value: Decodable>(_ type: Value.Type) throws -> Value {
      guard request.arguments.count <= ApplicationServiceRemappingRPC.maximumArgumentBytes else {
        throw ApplicationServiceRemappingRPCError(
          code: .argumentTooLarge,
          message: "Remapping RPC arguments exceed the service limit."
        )
      }
      do {
        return try decode(type)
      } catch let error as ApplicationServiceRemappingRPCError {
        throw error
      } catch {
        throw ApplicationServiceRemappingRPCError(
          code: .invalidArguments,
          message: "Remapping RPC arguments are malformed."
        )
      }
    }
    func sendRemapping<Value: Encodable & Sendable>(
      _ result: RemappingRequestResult<Value>
    ) {
      switch result {
      case .success(let value):
        do {
          let encodedValue = try JSONEncoder().encode(value)
          guard encodedValue.count <= ApplicationServiceRemappingRPC.maximumPayloadBytes else {
            throw ApplicationServiceRemappingRPCError(
              code: .responseTooLarge,
              message: "The remapping RPC response exceeds the service limit."
            )
          }
          let response = LocalServiceRPCResponse(result: encodedValue, error: nil)
          guard try JSONEncoder().encode(response).count
            <= ApplicationServiceRemappingRPC.maximumTransportFrameBytes
          else {
            throw ApplicationServiceRemappingRPCError(
              code: .responseTooLarge,
              message: "The remapping RPC response exceeds the transport frame limit."
            )
          }
          completion(
            response
          )
        } catch let error as ApplicationServiceRemappingRPCError {
          fail(error)
        } catch {
          fail(
            ApplicationServiceRemappingRPCError(
              code: .responseEncodingFailed,
              message: "The remapping RPC response could not be encoded."
            )
          )
        }
      case .failure(let error):
        fail(error)
      }
    }

    do {
      if let method = ApplicationServiceRemappingRPCMethod(rawValue: request.method) {
        switch method {
        case .getSnapshot:
          _ = try decodeRemapping(LocalServiceRPCEmptyArguments.self)
          getRemappingSnapshot(reply: sendRemapping)
        case .getProfile:
          let value = try decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
          getRemappingProfile(id: value.profileID, reply: sendRemapping)
        case .createProfile:
          let value = try decodeRemapping(ApplicationServiceRemappingProfileArguments.self)
          createRemappingProfile(value.profile, reply: sendRemapping)
        case .updateProfile:
          let value = try decodeRemapping(ApplicationServiceRemappingProfileUpdateArguments.self)
          updateRemappingProfile(
            value.profile,
            expectedCurrent: value.expectedCurrent,
            reply: sendRemapping
          )
        case .deleteProfile:
          let value = try decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
          deleteRemappingProfile(id: value.profileID, reply: sendRemapping)
        case .importProfile:
          let value = try decodeRemapping(ApplicationServiceRemappingProfileArguments.self)
          importRemappingProfile(value.profile, reply: sendRemapping)
        case .activateProfile:
          let value = try decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
          activateRemappingProfile(id: value.profileID, reply: sendRemapping)
        case .deactivateProfile:
          let value = try decodeRemapping(ApplicationServiceRemappingModelArguments.self)
          deactivateRemappingProfile(
            vendorID: value.vendorID,
            productID: value.productID,
            reply: sendRemapping
          )
        case .getPostEventAccess:
          _ = try decodeRemapping(LocalServiceRPCEmptyArguments.self)
          getRemappingPostEventAccess(reply: sendRemapping)
        case .requestPostEventAccess:
          _ = try decodeRemapping(LocalServiceRPCEmptyArguments.self)
          requestRemappingPostEventAccess(reply: sendRemapping)
        }
        return
      }

      switch request.method {
      case "listDevices":
        listDevices(reply: send)
      case "getStatus":
        getStatus(reply: send)
      case "requestRequiredAccess":
        requestRequiredAccess(reply: send)
      case "getDeviceInputState":
        let value = try decode(LocalServiceRPCDeviceArguments.self)
        getDeviceInputState(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          reply: send
        )
      case "getPacketLog":
        let value = try decode(LocalServiceRPCDeviceArguments.self)
        getPacketLog(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          reply: send
        )
      case "sendPhysicalRumble":
        let value = try decode(LocalServiceRPCRumbleArguments.self)
        sendPhysicalRumble(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          left: value.left,
          right: value.right,
          lt: value.leftTrigger,
          rt: value.rightTrigger,
          durationMs: value.durationMilliseconds,
          reply: send
        )
      case "setPhysicalPlayerIndicator":
        let value = try decode(LocalServiceRPCPlayerIndicatorArguments.self)
        setPhysicalPlayerIndicator(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          playerIndex: value.playerIndex,
          reply: send
        )
      case "setPhysicalColor":
        let value = try decode(LocalServiceRPCColorArguments.self)
        setPhysicalColor(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          red: value.red,
          green: value.green,
          blue: value.blue,
          reply: send
        )
      case "setPhysicalBrightness":
        let value = try decode(LocalServiceRPCBrightnessArguments.self)
        setPhysicalBrightness(
          vendorID: value.vendorID,
          productID: value.productID,
          runtimeIdentifier: value.runtimeIdentifier,
          brightness: value.brightness,
          reply: send
        )
      case "setSuppressOutput":
        setSuppressOutput(try decode(LocalServiceRPCBoolArguments.self).value, reply: send)
      case "getVirtualDeviceDiagnostics":
        getVirtualDeviceDiagnostics(reply: send)
      case "setCompatibilityIdentity":
        setCompatibilityIdentity(
          try decode(LocalServiceRPCStringArguments.self).value,
          reply: send
        )
      case "getCompatibilityIdentity":
        getCompatibilityIdentity(reply: send)
      case "runVirtualDeviceSelfTest":
        runVirtualDeviceSelfTest(
          seconds: try decode(LocalServiceRPCIntArguments.self).value,
          reply: send
        )
      case "resetSettings":
        resetSettings(reply: send)
      default:
        throw NSError(
          domain: "OpenJoystickDriver.LocalServiceRPC",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Unknown RPC method: \(request.method)"]
        )
      }
    } catch {
      fail(error)
    }
  }
}
