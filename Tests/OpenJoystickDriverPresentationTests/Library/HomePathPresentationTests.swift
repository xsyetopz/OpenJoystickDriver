import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

/// A path under the home folder is `~/…` where the app shows it; the path itself stays absolute.
struct HomePathPresentationTests {
  private static let home = MacOSDataDirectory().url(for: .home).path

  @Test
  func libraryListShowsSkippedFileUnderHomeFolderWithTilde() {
    let skipped = LibrarySkippedFile(
      path: "\(Self.home)/Library/Application Support/OpenJoystickDriver/Controllers/x.json",
      problem: "not a record"
    )

    #expect(
      skipped.displayPath
        == "~/Library/Application Support/OpenJoystickDriver/Controllers/x.json"
    )
    #expect(skipped.path.hasPrefix(Self.home))
  }

  @Test
  func libraryDetailShowsRecordFileWithTildeAndNothingForBundledRecord() {
    let file = URL(fileURLWithPath: "\(Self.home)/Records/054c-0268.patch.plist")
    let user = LibraryRecordItem(
      model: ControllerModelID(vendorID: 0x054C, productID: 0x0268),
      family: .sonySixaxis,
      layer: .user,
      file: file
    )
    let bundled = LibraryRecordItem(
      model: ControllerModelID(vendorID: 0x045E, productID: 0x028E),
      family: .xboxGIP,
      layer: .bundled,
      file: nil
    )

    #expect(user.fileDisplayPath == "~/Records/054c-0268.patch.plist")
    #expect(user.file == file)
    #expect(bundled.fileDisplayPath == nil)
  }

  @Test
  func accessListsShowClientPathUnderHomeFolderWithTilde() {
    #expect(
      AccessPresentation.location("\(Self.home)/Applications/Reader.app")
        == "~/Applications/Reader.app"
    )
    #expect(AccessPresentation.location("/Applications/Reader.app") == "/Applications/Reader.app")
  }

  @Test
  func controllerDetailRecordRowShowsUserRecordFileWithTilde() {
    let row = ControllerDetailFacts.recordLocation(
      "\(Self.home)/Records/054c-0268.patch.plist"
    )

    #expect(
      row
        == OJDLocalized.formatted(
          "cli.controller.show.recordUser",
          "~/Records/054c-0268.patch.plist"
        )
    )
  }
}
