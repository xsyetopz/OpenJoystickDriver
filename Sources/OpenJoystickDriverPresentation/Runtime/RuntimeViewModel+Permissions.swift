import Combine
import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// Reads the permissions from the service status again.
  ///
  /// They read as unknown until the answer arrives.
  func refreshPermissions() async {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .loading
    updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
    do {
      let payload = try await gateway.status()
      guard generation == permissionRefreshGeneration else { return }
      let presentation = RuntimeStatusPresentation(payload: payload)
      permissionState = .available(presentation.permissions)
      authoritativePermissionSummary = presentation.permissions
      updateStatusPermissions(presentation.permissions)
    } catch {
      guard generation == permissionRefreshGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
    }
  }

  /// Asks macOS, through the service, for the permissions that the service requires.
  ///
  /// Returns the permissions, or nil when the request failed or a later read or request replaced
  /// it.
  @discardableResult
  func requestPermissions() async -> RuntimePermissionSummary? {
    await requestPermissionSummary { try await gateway.requestPermissions() }
  }

  /// Asks macOS, through the service, for one permission.
  ///
  /// Returns the permissions, or nil when the request failed or a later read or request replaced
  /// it.
  @discardableResult
  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async -> RuntimePermissionSummary? {
    await requestPermissionSummary { try await gateway.requestPermission(requirement) }
  }

  /// Shows the permissions as requested while `request` runs, then shows its answer.
  ///
  /// Returns the permissions, or nil when the request failed or a later read or request replaced
  /// it.
  private func requestPermissionSummary(
    _ request: () async throws -> PermissionManager.Snapshot
  ) async -> RuntimePermissionSummary? {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .requesting
    updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
    do {
      let snapshot = try await request()
      guard generation == permissionRefreshGeneration else { return nil }
      let permissions = RuntimePermissionSummary(snapshot: snapshot)
      permissionState = .available(permissions)
      authoritativePermissionSummary = permissions
      updateStatusPermissions(permissions)
      return permissions
    } catch {
      guard generation == permissionRefreshGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
      return nil
    }
  }

  /// Asks macOS, through the service, for Bluetooth access.
  ///
  /// Returns the state at the answer, or nil when the request failed, with
  /// ``bluetoothRequestFailure`` saying why. The status shows the answer at once.
  @discardableResult
  func requestBluetoothAccess() async -> BluetoothAccessState? {
    bluetoothRequestFailure = nil
    let access: BluetoothAccessState
    do { access = try await gateway.requestBluetoothAccess() } catch {
      bluetoothRequestFailure = RuntimePresentation.userFacingError(error)
      return nil
    }
    if case .available(var presentation) = statusState {
      presentation.bluetoothAccess = access
      statusState = .available(presentation)
    }
    return access
  }

  /// Asks macOS for the Post Event access.
  ///
  /// Returns its state, or nil when the request failed or a later read or request replaced it.
  @discardableResult
  func requestPostEventAccess() async -> RemappingPostEventAccessState? {
    postEventAccessGeneration += 1
    let generation = postEventAccessGeneration
    authoritativePostEventAccess = nil
    postEventAccessState = .requesting
    updateStatusPostEventAccess(nil)
    do {
      let state = try await gateway.requestRemappingPostEventAccess()
      guard generation == postEventAccessGeneration else { return nil }
      postEventAccessState = .available(state)
      authoritativePostEventAccess = state
      updateStatusPostEventAccess(state)
      return state
    } catch {
      guard generation == postEventAccessGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      postEventAccessState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      authoritativePostEventAccess = nil
      updateStatusPostEventAccess(nil)
      return nil
    }
  }

  /// Reads the Post Event access again.
  func refreshPostEventAccess() async {
    postEventAccessGeneration += 1
    let generation = postEventAccessGeneration
    authoritativePostEventAccess = nil
    postEventAccessState = .loading
    updateStatusPostEventAccess(nil)
    do {
      let state = try await gateway.remappingPostEventAccess()
      guard generation == postEventAccessGeneration else { return }
      postEventAccessState = .available(state)
      authoritativePostEventAccess = state
      updateStatusPostEventAccess(state)
    } catch {
      guard generation == postEventAccessGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      postEventAccessState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      authoritativePostEventAccess = nil
      updateStatusPostEventAccess(nil)
    }
  }
}
