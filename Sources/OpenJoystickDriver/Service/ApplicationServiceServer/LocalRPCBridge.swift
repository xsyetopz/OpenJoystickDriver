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
      completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
    }

    do {
      switch request.method {
      case "listDevices":
        listDevices(reply: send)
      case "getStatus":
        getStatus(reply: send)
      case "requestRequiredAccess":
        requestRequiredAccess(reply: send)
      case "getDeviceInputState":
        let value = try decode(LocalServiceRPCDeviceArguments.self)
        getDeviceInputState(vendorID: value.vendorID, productID: value.productID, reply: send)
      case "getPacketLog":
        let value = try decode(LocalServiceRPCDeviceArguments.self)
        getPacketLog(vendorID: value.vendorID, productID: value.productID, reply: send)
      case "sendPhysicalRumble":
        let value = try decode(LocalServiceRPCRumbleArguments.self)
        sendPhysicalRumble(
          vendorID: value.vendorID,
          productID: value.productID,
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
          playerIndex: value.playerIndex,
          reply: send
        )
      case "setPhysicalColor":
        let value = try decode(LocalServiceRPCColorArguments.self)
        setPhysicalColor(
          vendorID: value.vendorID,
          productID: value.productID,
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
