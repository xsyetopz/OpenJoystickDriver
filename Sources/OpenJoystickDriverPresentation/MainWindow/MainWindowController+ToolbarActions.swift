#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension MainWindowController {
    /// Starts converting the selected profile, if one is selected.
    func convertSelectedProfile() {
      if let selectedProfile { screens.profiles.beginConverting(selectedProfile) }
    }

    /// Exports the selected profile, if one is selected.
    func exportSelectedProfile() {
      if let selectedProfile { screens.profiles.exportProfile(selectedProfile) }
    }

    /// Asks to delete the selected profile, if one is selected.
    func deleteSelectedProfile() {
      if let selectedProfile { screens.profiles.activeAlert = .delete(selectedProfile.id) }
    }

    /// Asks for a program and requests its access grant.
    func grantProgramAccess() {
      if let url = AccessFilePicker.chooseProgram() {
        screens.access.requestGrant(programAt: url)
      }
    }

    /// Asks for a record or mod folder and validates it.
    func validateLibraryFolder() {
      if let url = LibraryFilePicker.chooseRecordOrModFolder() {
        screens.libraryArea.validate(at: url)
      }
    }

    /// Asks for a capture and its expectation and tests the selected record against them.
    func testSelectedLibraryRecord() {
      if let capture = LibraryFilePicker.chooseCapture(),
        let expectation = LibraryFilePicker.chooseExpectation()
      {
        screens.libraryArea.testSelectedRecord(capture: capture, expectation: expectation)
      }
    }
  }

#endif
