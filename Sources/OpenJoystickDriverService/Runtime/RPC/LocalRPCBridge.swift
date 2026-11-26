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

/// Decodes the arguments of one RPC request and encodes its result.
///
/// The remapping variants bound the argument and response sizes and report each failure as
/// ``ApplicationServiceRemappingRPCError``.
private struct LocalRPCCall {
  let request: LocalServiceRPCRequest

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

  /// Sends `request` to the handler of its method and encodes the result.
  ///
  /// - Throws: An error for an unknown method, malformed arguments or a failed handler.
  private func response(to request: LocalServiceRPCRequest) async throws -> LocalServiceRPCResponse
  {
    guard let method = ApplicationServiceRPCMethod(rawValue: request.method) else {
      throw NSError(
        domain: "OpenJoystickDriver.LocalServiceRPC",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Unknown RPC method: \(request.method)"]
      )
    }
    let call = LocalRPCCall(request: request)
    // One exhaustive table, so adding a method without a handler fails to compile.
    switch method {
    case .getStatus:
      _ = try call.decode(LocalServiceRPCEmptyArguments.self)
      return try call.send(await getStatus())
    case .requestRequiredAccess:
      _ = try call.decode(LocalServiceRPCEmptyArguments.self)
      return try call.send(await requestRequiredAccess())
    case .requestAccess:
      let value = try call.decode(LocalServiceRPCPermissionArguments.self)
      return try call.send(await requestAccess(value.requirement))
    case .requestBluetoothAccess:
      _ = try call.decode(LocalServiceRPCEmptyArguments.self)
      return try call.send(requestBluetoothAccess())
    case .getControllerState:
      let value = try call.decode(LocalServiceRPCDeviceArguments.self)
      return try call.send(await getControllerState(for: value.controller))
    case .getVirtualOutputState:
      let value = try call.decode(LocalServiceRPCDeviceArguments.self)
      return try call.send(await getVirtualOutputState(for: value.controller))
    case .getPacketLog:
      let value = try call.decode(LocalServiceRPCDeviceArguments.self)
      return try call.send(await getPacketLog(for: value.controller))
    case .sendControllerOutput:
      let value = try call.decode(LocalServiceRPCControllerOutputArguments.self)
      return try call.send(await sendControllerOutput(value.command, for: value.controller))
    case .sendRawControllerOutput:
      let value = try call.decode(LocalServiceRPCRawOutputArguments.self)
      return try call.send(await sendRawControllerOutput(value.output, for: value.controller))
    case .playControllerSpeaker:
      let value = try call.decode(LocalServiceRPCSpeakerArguments.self)
      return try call.send(await playControllerSpeaker(value.audio, for: value.controller))
    case .stopControllerSpeaker:
      let value = try call.decode(LocalServiceRPCDeviceArguments.self)
      return try call.send(await stopControllerSpeaker(for: value.controller))
    case .previewPhysicalColor:
      return try await previewPhysicalColorResponse(call)
    case .releasePhysicalColorPreview:
      let value = try call.decode(LocalServiceRPCColorPreviewReleaseArguments.self)
      return try call.send(
        await releasePhysicalColorPreview(for: value.controller, token: value.token)
      )
    case .getVirtualDeviceDiagnostics:
      _ = try call.decode(LocalServiceRPCEmptyArguments.self)
      return try call.send(getVirtualDeviceDiagnostics())
    case .getFrameTimings:
      return try await frameTimingsResponse(call)
    case .waitForServiceStatusChange:
      let value = try call.decode(LocalServiceRPCStatusChangeArguments.self)
      return try call.send(
        await statusChanges.wait(after: value.after, holdSeconds: ServiceStatusRevision.holdSeconds)
      )
    case .sendTestNotification:
      return try await testNotificationResponse(call)
    case .reportTestNotificationResult:
      return try testNotificationReportResponse(call)
    case .setVirtualHIDProfileOverride:
      let value = try call.decode(LocalServiceRPCVirtualHIDProfileOverrideArguments.self)
      return try call.send(
        await setVirtualHIDProfileOverride(value.profile, for: value.controller, unit: value.unit)
      )
    case .resetVirtualHIDProfileOverride:
      let value = try call.decode(LocalServiceRPCVirtualHIDProfileOverrideResetArguments.self)
      return try call.send(
        await resetVirtualHIDProfileOverride(for: value.controller, unit: value.unit)
      )
    case .setControllerServer:
      let value = try call.decode(LocalServiceRPCControllerServerArguments.self)
      return try call.send(
        await setControllerServer(
          vendorID: value.vendorID,
          productID: value.productID,
          server: value.server
        )
      )
    case .recalibrateController:
      return try call.send(
        await recalibrateController(call.decode(ControllerRecalibrationArguments.self))
      )
    case .setControllerTuning:
      let value = try call.decode(LocalServiceRPCControllerTuningArguments.self)
      return try call.send(
        setControllerTuning(
          vendorID: value.vendorID,
          productID: value.productID,
          key: value.key,
          value: value.value
        )
      )
    case .openVirtualFeed:
      let value = try call.decode(LocalServiceRPCVirtualFeedOpenArguments.self)
      return try call.send(try await virtualFeeds.open(profile: value.profile))
    case .exchangeVirtualFeed:
      let value = try call.decode(LocalServiceRPCVirtualFeedExchangeArguments.self)
      return try call.send(virtualFeeds.exchange(token: value.token, frames: value.frames))
    case .waitForVirtualFeedFeedback:
      return try await virtualFeedFeedbackResponse(call)
    case .closeVirtualFeed:
      let value = try call.decode(LocalServiceRPCVirtualFeedCloseArguments.self)
      return try call.send(await virtualFeeds.close(token: value.token))
    case .suspendController:
      let value = try call.decode(LocalServiceRPCDeviceArguments.self)
      return try call.send(await suspendController(value.controller))
    case .resumeController:
      let value = try call.decode(LocalServiceRPCDeviceArguments.self)
      return try call.send(await resumeController(value.controller))
    case .disconnectWirelessController:
      let value = try call.decode(LocalServiceRPCDeviceArguments.self)
      return try call.send(await disconnectWirelessController(value.controller))
    case .resetSettings:
      _ = try call.decode(LocalServiceRPCEmptyArguments.self)
      return try call.send(await resetSettings())
    case .getSettings:
      _ = try call.decode(LocalServiceRPCEmptyArguments.self)
      return try call.send(getSettings())
    case .setSetting:
      let value = try call.decode(ApplicationServiceSettingArguments.self)
      return try call.send(try setSetting(value.key, to: value.value))
    case .getAccessStatus:
      _ = try call.decode(LocalServiceRPCEmptyArguments.self)
      return try call.send(try getAccessStatus())
    case .setAccessEnabled:
      return try call.send(
        try setAccessEnabled(try call.decode(AccessEnabledArguments.self).enabled)
      )
    case .grantAccess:
      return try call.send(try grantAccess(try call.decode(AccessGrantArguments.self)))
    case .revokeAccess:
      return try call.send(try revokeAccess(try call.decode(AccessRevokeArguments.self)))
    case .grantTokenAccess:
      return try call.send(try grantTokenAccess(try call.decode(AccessTokenGrantArguments.self)))
    case .setWebAccess:
      return try call.send(try setWebAccess(try call.decode(AccessWebArguments.self)))
    case .remappingMotionCalibration:
      let value = try call.decodeRemapping(ApplicationServiceMotionCalibrationArguments.self)
      return try call.sendRemapping(try await remappingMotionCalibration(value))
    case .pairRemappingJoyCons:
      let value = try call.decodeRemapping(ApplicationServiceJoyConPairArguments.self)
      return try call.sendRemapping(try await pairRemappingJoyCons(value))
    case .unpairRemappingJoyCons:
      let value = try call.decodeRemapping(ApplicationServiceJoyConUnpairArguments.self)
      return try call.sendRemapping(try await unpairRemappingJoyCons(value))
    case .getRemappingSnapshot:
      _ = try call.decodeRemapping(LocalServiceRPCEmptyArguments.self)
      return try call.sendRemapping(try await getRemappingSnapshot())
    case .getRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
      return try call.sendRemapping(try await getRemappingProfile(id: value.profileID))
    case .createRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileArguments.self)
      return try call.sendRemapping(try await createRemappingProfile(value.profile))
    case .updateRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileUpdateArguments.self)
      return try call.sendRemapping(
        try await updateRemappingProfile(value.profile, expectedCurrent: value.expectedCurrent)
      )
    case .deleteRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
      return try call.sendRemapping(try await deleteRemappingProfile(id: value.profileID))
    case .deleteDamagedRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileIssueArguments.self)
      return try call.sendRemapping(try await deleteDamagedRemappingProfile(value))
    case .resetRemappingProfileLibrary:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileIssueArguments.self)
      return try call.sendRemapping(try await resetRemappingProfileLibrary(value))
    case .importRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileArguments.self)
      return try call.sendRemapping(try await importRemappingProfile(value.profile))
    case .activateRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingActivateArguments.self)
      return try call.sendRemapping(
        try await activateRemappingProfile(id: value.profileID, allowEmpty: value.allowEmpty)
      )
    case .deactivateRemappingProfile:
      let value = try call.decodeRemapping(ApplicationServiceRemappingModelArguments.self)
      return try call.sendRemapping(
        try await deactivateRemappingProfile(vendorID: value.vendorID, productID: value.productID)
      )
    case .deactivateRemappingProfileByID:
      let value = try call.decodeRemapping(ApplicationServiceRemappingProfileIDArguments.self)
      return try call.sendRemapping(try await deactivateRemappingProfile(id: value.profileID))
    case .getRemappingPostEventAccess:
      _ = try call.decodeRemapping(LocalServiceRPCEmptyArguments.self)
      return try call.sendRemapping(try await getRemappingPostEventAccess())
    case .requestRemappingPostEventAccess:
      _ = try call.decodeRemapping(LocalServiceRPCEmptyArguments.self)
      return try call.sendRemapping(try await requestRemappingPostEventAccess())
    }
  }

  private func previewPhysicalColorResponse(
    _ call: LocalRPCCall
  ) async throws
    -> LocalServiceRPCResponse
  {
    let value = try call.decode(LocalServiceRPCColorPreviewArguments.self)
    return try call.send(
      await previewPhysicalColor(
        for: value.controller,
        token: value.token,
        red: value.red,
        green: value.green,
        blue: value.blue
      )
    )
  }

  /// Rejects a window outside ``FrameTimingRecorder/windowSecondsRange`` before reading timings.
  private func frameTimingsResponse(_ call: LocalRPCCall) async throws -> LocalServiceRPCResponse {
    let value = try call.decode(LocalServiceRPCFrameTimingsArguments.self)
    if let lastSeconds = value.lastSeconds,
      !FrameTimingRecorder.windowSecondsRange.contains(lastSeconds)
    {
      throw FrameTimingsRequestError.invalidRequest
    }
    return try call.send(await getFrameTimings(lastSeconds: value.lastSeconds))
  }

  /// Throws `CancellationError` when the announcement ends with no outcome.
  private func testNotificationResponse(
    _ call: LocalRPCCall
  ) async throws
    -> LocalServiceRPCResponse
  {
    _ = try call.decode(LocalServiceRPCEmptyArguments.self)
    guard let outcome = await statusChanges.announceTestNotification() else {
      throw CancellationError()
    }
    return try call.send(outcome)
  }

  /// Refuses a `noAnswer` report, an outcome only the service decides.
  private func testNotificationReportResponse(
    _ call: LocalRPCCall
  ) throws
    -> LocalServiceRPCResponse
  {
    let value = try call.decode(TestNotificationReport.self)
    if case .noAnswer = value.outcome { throw TestNotificationReportError.noAnswerReported }
    return try call.send(
      statusChanges.reportTestNotification(value.announcement, outcome: value.outcome)
    )
  }

  /// Clamps the requested wait to `0...maximumTimeoutMilliseconds`.
  private func virtualFeedFeedbackResponse(
    _ call: LocalRPCCall
  ) async throws
    -> LocalServiceRPCResponse
  {
    let value = try call.decode(LocalServiceRPCVirtualFeedWaitArguments.self)
    let milliseconds = min(
      max(0, value.timeoutMilliseconds),
      LocalServiceRPCVirtualFeedWaitArguments.maximumTimeoutMilliseconds
    )
    return try call.send(
      await virtualFeeds.waitForFeedback(
        token: value.token,
        timeout: TimeInterval(milliseconds) / 1000
      )
    )
  }
}
