import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

struct AccessPermissionStateTests {
  @Test
  func everyStateHasItsOwnSymbolShape() {
    let names = AccessPermissionState.allCases.map(\.symbolName)
    #expect(Set(names).count == names.count)
    let shapes = names.map { $0.split(separator: ".").prefix(2).joined(separator: ".") }
    #expect(Set(shapes).count == names.count)
  }

  @Test
  func onlyStatesWhoseValueLeavesSomethingOutHaveASentence() {
    let explained = AccessPermissionState.allCases.filter { $0.messageKey != nil }
    #expect(explained == [.denied, .notNeeded, .limited])
    let keys = explained.compactMap(\.messageKey)
    #expect(Set(keys).count == keys.count)
    for key in keys { #expect(OJDLocalized.string(key) != key) }
  }

  @Test(arguments: AccessPermissionRow.Kind.allCases)
  func everyPermissionSaysWhatItIsFor(kind: AccessPermissionRow.Kind) {
    #expect(OJDLocalized.string(kind.purposeKey) != kind.purposeKey)
  }

  @Test
  func readinessStatusesCarryTheirState() {
    let granted = AccessReadiness(
      permissionState: .available(
        RuntimePermissionSummary(inputRead: .granted, inputInject: .denied)
      ),
      statusState: .loading,
      notificationState: .notDetermined,
      notificationSettings: .authorizationOnly(.notDetermined)
    )
    #expect(granted.inputRead.state == .granted)
    #expect(granted.inputInject.state == .denied)
    #expect(granted.notification.state == .notAsked)
    let checking = AccessReadiness(
      permissionState: .loading,
      statusState: .loading,
      notificationState: .checking,
      notificationSettings: .authorizationOnly(.checking)
    )
    #expect(checking.inputRead.state == .checking)
    #expect(checking.postEvent.state == .checking)
  }
}
