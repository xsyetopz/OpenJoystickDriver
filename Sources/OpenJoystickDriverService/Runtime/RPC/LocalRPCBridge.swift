import Foundation
import OpenJoystickDriverKit

/// Why the service refuses a `reportTestNotificationResult` request.
enum TestNotificationReportError: Error, LocalizedError, Equatable {
  /// The report's outcome is `noAnswer`, which only the service decides when no app answers.
  case noAnswerReported

  /// The localized message of the refusal.
  var errorDescription: String? {
    switch self {
    case .noAnswerReported:
      Localization().string("ui.settings.notifications.testReportNoAnswer")
    }
  }
}

/// Why the service refuses a `getFrameTimings` request.
enum FrameTimingsRequestError: Error, LocalizedError, Equatable {
  /// `lastSeconds` is outside ``FrameTimingRecorder/windowSecondsRange``.
  case invalidRequest

  /// The localized message of the refusal.
  var errorDescription: String? {
    switch self {
    case .invalidRequest:
      Localization().string("cli.diagnose.group.framesInvalidRequest")
    }
  }
}

extension ApplicationServiceServer {
  /// Decodes `request`, awaits its handler, and encodes the value or error as the response.
  func handleLocalRPC(_ request: LocalServiceRPCRequest) async -> LocalServiceRPCResponse {
    do { return try await response(to: request) } catch let error
      as ApplicationServiceRemappingRPCError
    { return LocalServiceRPCResponse(remappingError: error) } catch {
      return LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
    }
  }

  /// Dispatches `request` to the handler of its method and encodes the result.
  ///
  /// Remapping methods bound the argument and response sizes and report failures as
  /// ``ApplicationServiceRemappingRPCError``.
  ///
  /// - Throws: An error for an unknown method, malformed arguments or a failed handler.
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
    case .requestBluetoothAccess:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(requestBluetoothAccess())
    case .getControllerState:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await getControllerState(
          for: value.controller
        )
      )
    case .getVirtualOutputState:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await getVirtualOutputState(
          for: value.controller
        )
      )
    case .getPacketLog:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await getPacketLog(
          for: value.controller
        )
      )
    case .sendControllerOutput:
      let value = try decode(LocalServiceRPCControllerOutputArguments.self)
      return try send(
        await sendControllerOutput(
          value.command,
          for: value.controller
        )
      )
    case .playControllerSpeaker:
      let value = try decode(LocalServiceRPCSpeakerArguments.self)
      return try send(await playControllerSpeaker(value.audio, for: value.controller))
    case .stopControllerSpeaker:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(await stopControllerSpeaker(for: value.controller))
    case .previewPhysicalColor:
      let value = try decode(LocalServiceRPCColorPreviewArguments.self)
      return try send(
        await previewPhysicalColor(
          for: value.controller,
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
          for: value.controller,
          token: value.token
        )
      )
    case .getVirtualDeviceDiagnostics:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(getVirtualDeviceDiagnostics())
    case .getFrameTimings:
      let value = try decode(LocalServiceRPCFrameTimingsArguments.self)
      if let lastSeconds = value.lastSeconds,
        !FrameTimingRecorder.windowSecondsRange.contains(lastSeconds)
      {
        throw FrameTimingsRequestError.invalidRequest
      }
      return try send(await getFrameTimings(lastSeconds: value.lastSeconds))
    case .waitForServiceStatusChange:
      let value = try decode(LocalServiceRPCStatusChangeArguments.self)
      return try send(
        await statusChanges.wait(
          after: value.after,
          holdSeconds: ServiceStatusRevision.holdSeconds
        )
      )
    case .sendTestNotification:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      guard let outcome = await statusChanges.announceTestNotification() else {
        throw CancellationError()
      }
      return try send(outcome)
    case .reportTestNotificationResult:
      let value = try decode(TestNotificationReport.self)
      if case .noAnswer = value.outcome { throw TestNotificationReportError.noAnswerReported }
      return try send(
        statusChanges.reportTestNotification(value.announcement, outcome: value.outcome)
      )
    case .setVirtualHIDProfileOverride:
      let value = try decode(LocalServiceRPCVirtualHIDProfileOverrideArguments.self)
      return try send(
        await setVirtualHIDProfileOverride(
          value.profile,
          for: value.controller,
          unit: value.unit
        )
      )
    case .resetVirtualHIDProfileOverride:
      let value = try decode(LocalServiceRPCVirtualHIDProfileOverrideResetArguments.self)
      return try send(
        await resetVirtualHIDProfileOverride(
          for: value.controller,
          unit: value.unit
        )
      )
    case .setControllerServer:
      let value = try decode(LocalServiceRPCControllerServerArguments.self)
      return try send(
        await setControllerServer(
          vendorID: value.vendorID,
          productID: value.productID,
          server: value.server
        )
      )
    case .setControllerTuning:
      let value = try decode(LocalServiceRPCControllerTuningArguments.self)
      return try send(
        setControllerTuning(
          vendorID: value.vendorID,
          productID: value.productID,
          key: value.key,
          value: value.value
        )
      )
    case .openVirtualFeed:
      let value = try decode(LocalServiceRPCVirtualFeedOpenArguments.self)
      return try send(try await virtualFeeds.open(profile: value.profile))
    case .exchangeVirtualFeed:
      let value = try decode(LocalServiceRPCVirtualFeedExchangeArguments.self)
      return try send(virtualFeeds.exchange(token: value.token, frames: value.frames))
    case .closeVirtualFeed:
      let value = try decode(LocalServiceRPCVirtualFeedCloseArguments.self)
      return try send(await virtualFeeds.close(token: value.token))
    case .suspendController:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await suspendController(
          value.controller
        )
      )
    case .resumeController:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await resumeController(
          value.controller
        )
      )
    case .disconnectWirelessController:
      let value = try decode(LocalServiceRPCDeviceArguments.self)
      return try send(
        await disconnectWirelessController(
          value.controller
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
    case .getAccessStatus:
      _ = try decode(LocalServiceRPCEmptyArguments.self)
      return try send(try getAccessStatus())
    case .setAccessEnabled:
      return try send(try setAccessEnabled(try decode(AccessEnabledArguments.self).enabled))
    case .grantAccess:
      return try send(try grantAccess(try decode(AccessGrantArguments.self)))
    case .revokeAccess:
      return try send(try revokeAccess(try decode(AccessRevokeArguments.self)))
    case .grantTokenAccess:
      return try send(try grantTokenAccess(try decode(AccessTokenGrantArguments.self)))
    case .setWebAccess:
      return try send(try setWebAccess(try decode(AccessWebArguments.self)))
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
      let value = try decodeRemapping(ApplicationServiceRemappingActivateArguments.self)
      return try sendRemapping(
        try await activateRemappingProfile(id: value.profileID, allowEmpty: value.allowEmpty)
      )
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
