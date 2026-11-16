import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct AccessReadinessTests {
  private func readiness(
    permissions: RuntimePermissionLoadState,
    notification: RuntimeNotificationAuthorizationState = .allowed,
    settings: RuntimeNotificationSettings? = nil
  ) -> AccessReadiness {
    AccessReadiness(
      permissionState: permissions,
      statusState: .loading,
      notificationState: notification,
      notificationSettings: settings ?? .authorizationOnly(notification)
    )
  }

  @Test
  func grantedInputPermissionsNeedNoRestart() {
    let value = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .granted, inputInject: .granted))
    )

    #expect(value.inputRead.tone == .positive)
    #expect(!value.inputRead.isActionable)
    #expect(!value.needsRestart)
  }

  @Test
  func deniedInputPermissionIsActionableAndOffersRestart() {
    let value = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .denied, inputInject: .granted))
    )

    #expect(value.inputRead.tone == .caution)
    #expect(value.inputRead.isActionable)
    #expect(value.inputInject.tone == .positive)
    #expect(value.needsRestart)
  }

  @Test
  func permissionsStillLoadingAreChecking() {
    let value = readiness(permissions: .loading)

    #expect(value.inputRead.tone == .neutral)
    #expect(value.inputRead.value == OJDLocalized.string("status.checking"))
    #expect(!value.needsRestart)
  }

  @Test
  func postEventAccessIsCheckingUntilStatusArrives() {
    let value = readiness(permissions: .unavailable)

    #expect(value.postEvent.value == OJDLocalized.string("status.checking"))
    #expect(value.postEvent.isActionable)
  }

  @Test
  func notificationsWithBannersOffNeedAttention() {
    let value = readiness(
      permissions: .unavailable,
      settings: RuntimeNotificationSettings(
        authorization: .allowed,
        alertStyle: .none,
        soundsEnabled: true
      )
    )

    #expect(
      value.notification.value
        == OJDLocalized.string("ui.settings.notifications.notificationBannersOff")
    )
    #expect(value.notification.isActionable)
  }

  @Test
  func notificationsAllowedWithBannersAndSoundAreReady() {
    let value = readiness(
      permissions: .unavailable,
      settings: RuntimeNotificationSettings(
        authorization: .allowed,
        alertStyle: .banner,
        soundsEnabled: true
      )
    )

    #expect(value.notification.tone == .positive)
    #expect(!value.notification.isActionable)
  }

  @Test
  func notificationsNotYetRequestedAreActionable() {
    let value = readiness(permissions: .unavailable, notification: .notDetermined)

    #expect(value.notification.value == OJDLocalized.string("status.notRequested"))
    #expect(value.notification.isActionable)
  }

  @Test
  func allowedPermissionsHaveNoButton() {
    let value = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .granted, inputInject: .granted))
    )

    #expect(value.rows.filter { $0.kind != .postEvent }.allSatisfy { $0.actionTitleKey == nil })
  }

  @Test
  func missingPermissionOffersSystemSettingsAndNotRequestedOneAsksFirst() {
    let denied = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .denied, inputInject: .granted))
    )
    let notRequested = readiness(permissions: .unavailable, notification: .notDetermined)

    #expect(
      denied.rows.first { $0.kind == .inputRead }?.actionTitleKey
        == "platform.macos.ui.setup.openSystemSettings"
    )
    #expect(denied.rows.first { $0.kind == .inputInject }?.actionTitleKey == nil)
    #expect(
      notRequested.rows.first { $0.kind == .notification }?.actionTitleKey == "action.request"
    )
  }

  private func status(
    postEvent: RemappingPostEventAccessState?,
    requiresPostEvent: Bool?,
    inputRead: PermissionManager.AccessState = .granted
  ) -> RuntimeStatusState {
    .available(
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          inputRead: inputRead,
          inputInject: .granted,
          connectedDevices: [],
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready")
        ),
        postEventAccess: postEvent,
        requiresPostEventAccess: requiresPostEvent
      )
    )
  }

  @Test
  func checkingPermissionHasNoButton() {
    let value = readiness(permissions: .loading)

    #expect(value.rows.first { $0.kind == .inputRead }?.actionTitleKey == nil)
  }

  @Test
  func postEventPermissionThatIsNotNeededHasNoRow() {
    let notNeeded = AccessReadiness(
      permissionState: .loading,
      statusState: .available(
        RuntimeStatusPresentation(
          payload: ApplicationServiceStatusPayload(
            inputRead: .granted,
            inputInject: .granted,
            connectedDevices: [],
            userSpaceVirtualDeviceEnabled: true,
            userSpaceVirtualDeviceStatus: .backend("ready")
          ),
          requiresPostEventAccess: false
        )
      ),
      notificationState: .allowed,
      notificationSettings: .authorizationOnly(.allowed)
    )

    #expect(
      notNeeded.rows.map { $0.kind } == [
        AccessPermissionRow.Kind.inputRead, .inputInject, .notification,
      ]
    )
    #expect(
      readiness(permissions: .loading).rows.map { $0.kind }
        == [AccessPermissionRow.Kind.inputRead, .inputInject, .postEvent, .notification]
    )
  }

  @Test
  func noPermissionIsMissingWhenAllAreGrantedOrNothingWasRead() {
    let granted = RuntimePermissionLoadState.available(
      RuntimePermissionSummary(inputRead: .granted, inputInject: .granted)
    )
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: granted,
        statusState: status(postEvent: .granted, requiresPostEvent: true)
      )
    )
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: granted,
        statusState: status(postEvent: nil, requiresPostEvent: false)
      )
    )
    #expect(
      !AccessReadiness.hasMissingPermission(permissionState: .unavailable, statusState: .loading)
    )
    #expect(!AccessReadiness.hasMissingPermission(permissionState: .loading, statusState: .loading))
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: .unavailable,
        statusState: .unavailable("down")
      )
    )
  }

  @Test
  func appsOwnPermissionReadingDecidesOverStatusPayload() {
    let granted = RuntimePermissionLoadState.available(
      RuntimePermissionSummary(inputRead: .granted, inputInject: .granted)
    )
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: granted,
        statusState: status(postEvent: .granted, requiresPostEvent: false, inputRead: .denied)
      )
    )
  }

  @Test
  func deniedUnknownOrUnauthorizedPermissionIsMissing() {
    func summary(
      _ read: RuntimePermissionState,
      _ inject: RuntimePermissionState
    )
      -> RuntimePermissionLoadState
    {
      .available(RuntimePermissionSummary(inputRead: read, inputInject: inject))
    }
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: summary(.denied, .granted),
        statusState: .loading
      )
    )
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: summary(.granted, .unknown),
        statusState: .loading
      )
    )
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: summary(.granted, .granted),
        statusState: status(postEvent: .notAuthorized, requiresPostEvent: true)
      )
    )
  }

  @Test
  func permissionsBeingReadOrRequestedAreCheckingNotMissing() {
    let placeholder = status(postEvent: nil, requiresPostEvent: false, inputRead: .unknown)
    for state in [RuntimePermissionLoadState.requesting, .loading] {
      #expect(
        !AccessReadiness.hasMissingPermission(permissionState: state, statusState: placeholder)
      )
    }
    #expect(
      !AccessReadiness.hasMissingPermission(permissionState: .unavailable, statusState: .loading)
    )
  }

  @Test
  func failedPermissionReadIsMissingBecauseAccessAreaSaysNeedsAttention() {
    let placeholder = status(postEvent: nil, requiresPostEvent: false, inputRead: .unknown)
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: .error("failed"),
        statusState: placeholder
      )
    )
    let value = readiness(permissions: .error("failed"))
    #expect(value.inputRead.tone == .caution)
  }

  @Test
  func statusReadingDecidesWhileAppHasNotReadPermissions() {
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: .unavailable,
        statusState: status(postEvent: nil, requiresPostEvent: false, inputRead: .denied)
      )
    )
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: .unavailable,
        statusState: status(postEvent: nil, requiresPostEvent: false, inputRead: .granted)
      )
    )
  }
}
