import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfilePresentationTests {
  @Test
  func focusedEditorContainsEverySectionInTaskOrder() {
    #expect(
      ProfilePresentationPolicy.sectionOrder == [
        .assignments, .combinations, .layers, .macros, .controller,
      ]
    )
    #expect(ProfilePresentationPolicy.defaultSection == .assignments)
  }

  @Test
  func sectionNavigationUsesAvailableEditorWidth() {
    #expect(ProfilePresentationPolicy.navigationStyle(for: 619) == .popUp)
    #expect(ProfilePresentationPolicy.navigationStyle(for: 620) == .segmented)
  }

  @Test
  func assignmentRowsStackOnlyBelowTheirReadableWidth() {
    #expect(ProfilePresentationPolicy.assignmentRowLayout(for: 679) == .stacked)
    #expect(ProfilePresentationPolicy.assignmentRowLayout(for: 680) == .inline)
  }

  @Test
  func optionalEditorsGrowOnlyWhenTheirFeatureIsEnabled() {
    #expect(
      ProfilePresentationPolicy.optionalEditorHeight(enabled: false, compact: 260, expanded: 600)
        == 260
    )
    #expect(
      ProfilePresentationPolicy.optionalEditorHeight(enabled: true, compact: 260, expanded: 600)
        == 600
    )
  }

  @Test
  @MainActor
  func librarySelectionRemainsStableUntilItsSelectedItemDisappears() {
    let profile = makeProfile(name: "Healthy")
    let damaged = ApplicationServiceRemappingProfileIssue(
      id: UUID(),
      kind: .damagedProfile,
      code: .invalidProfile,
      message: "damaged"
    )
    let unusable = ApplicationServiceRemappingProfileIssue(
      id: UUID(),
      kind: .unusableLibrary,
      code: .corruptLibrary,
      message: "unusable"
    )
    let model = ProfilesViewModel()
    let partial = ApplicationServiceRemappingSnapshotPayload(
      profiles: [profile],
      activeProfiles: [],
      routes: [],
      profileIssues: [damaged],
      postEventAccess: .granted
    )

    model.reconcileSelection(with: partial)
    #expect(model.selectedProfileID == profile.id)
    model.selectedRecoveryIssueID = damaged.id
    model.reconcileSelection(with: partial)
    #expect(model.selectedRecoveryIssueID == damaged.id)

    let unrecoverable = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      profileIssues: [unusable],
      postEventAccess: .granted
    )
    model.reconcileSelection(with: unrecoverable)
    #expect(model.selectedRecoveryIssueID == unusable.id)
    #expect(model.selectedProfileID == nil)
  }
}
