import AppKit
import Foundation
import OpenJoystickDriverKit

/// The result of checking a profile file without adding it, the check `ojd profile validate`
/// runs: a valid profile with what it targets, or the problem with its error code.
enum ProfileFileValidation: Equatable, Identifiable {
  /// A valid profile, with its name, its controller as vendor and product ID, and its application
  /// scope.
  case valid(name: String, controller: String, scope: String)
  /// A file that is not a valid profile, with the file name, the error code and the problem.
  case invalid(fileName: String, code: String, problem: String)

  /// Checks the contents of the file named `fileName` with the loader that import and the CLI use.
  ///
  /// - Parameters:
  ///   - data: The contents of the file.
  ///   - fileName: The name of the file, which the invalid result repeats.
  /// - Returns: The valid result with the profile's name, controller and scope, or the invalid
  ///   result with the problem.
  static func check(_ data: Data, fileName: String) -> Self {
    do {
      let profile = try RemappingProfileFileStore.load(from: data)
      let scope: String
      switch profile.applicationScope {
      case .global: scope = RuntimePresentation.profileScopeLabel(.global)
      case .application(let appID): scope = appID
      }
      return .valid(
        name: profile.name,
        controller: OJDValue.usbIdentifier(
          vendorID: profile.device.vendorID,
          productID: profile.device.productID
        ).displayText,
        scope: scope
      )
    } catch {
      return .invalid(
        fileName: fileName,
        code: RemappingProfileFileStore.problemCode(error).rawValue,
        problem: DocumentProblem.describe(error)
      )
    }
  }

  /// A string that tells the results apart: the title with the message.
  var id: String { title + message }

  /// The title of the result: valid or invalid.
  var title: String {
    switch self {
    case .valid: return OJDLocalized.string("ui.profiles.validTitle")
    case .invalid: return OJDLocalized.string("ui.profiles.invalidTitle")
    }
  }

  /// The text of the result: what the profile targets, or the problem with its error code.
  var message: String {
    switch self {
    case .valid(let name, let controller, let scope):
      return OJDLocalized.formatted("ui.profiles.validMessage", name, controller, scope)
    case .invalid(let fileName, let code, let problem):
      return OJDLocalized.formatted(
        "ui.error.withCode",
        OJDLocalized.formatted("cli.profile.group.documentInvalid", fileName, problem),
        code
      )
    }
  }
}

/// How the Profiles list names the application a profile is limited to.
enum ProfileScopeCaption {
  /// Returns the caption under a profile's name: the assignment count for a profile that applies
  /// to every application, else the application's name (the identifier when `resolveName` does
  /// not find it) and the count.
  ///
  /// - Parameters:
  ///   - scope: The application scope of the profile.
  ///   - assignments: The text that counts the assignments of the profile.
  ///   - resolveName: Returns the name of the application with the identifier, or nil.
  /// - Returns: The caption under a profile's name: the assignment count for a profile that applies
  ///   to every application, else the application's name (the identifier when `resolveName` does
  ///   not find it) and the count.
  static func text(
    for scope: RemappingApplicationScope,
    assignments: String,
    resolveName: (String) -> String?
  ) -> String {
    switch scope {
    case .global: return assignments
    case .application(let appID):
      return OJDLocalized.formatted(
        "ui.profiles.scopedCaption",
        resolveName(appID) ?? appID,
        assignments
      )
    }
  }
}

/// The installed applications' names by bundle identifier.
///
/// Each identifier is looked up once per session, so the list does not ask LaunchServices again on
/// every redraw.
@MainActor
final class ProfileApplicationNames {
  /// The names found so far; a nil value records an application that LaunchServices does not
  /// find.
  private var names: [String: String?] = [:]

  /// Returns the display name of the application with the bundle identifier, or nil when
  /// LaunchServices does not find it.
  func name(for bundleIdentifier: String) -> String? {
    if let known = names[bundleIdentifier] { return known }
    let name = Self.lookUp(bundleIdentifier)
    names[bundleIdentifier] = .some(name)
    return name
  }

  /// Looks up the display name of the application with the bundle identifier in LaunchServices.
  private static func lookUp(_ bundleIdentifier: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return nil }
    return FileManager.default.displayName(atPath: url.path)
  }
}
