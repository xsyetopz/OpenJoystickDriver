import Foundation

/// A client that holds a controller open, as a registry property names it.
///
/// A USB interface's `UsbExclusiveOwner` names its exclusive holder, and a user client's
/// `IOUserClientCreator` names the process that opened it. A user-space client is named
/// `pid <number>, <process name>`; the kernel truncates the process name to 16 characters. A
/// kernel driver is named by its class, such as `AppleUSB20Hub`, and carries no process ID.
public struct USBExclusiveOwner: Codable, Equatable, Sendable {
  /// The owning process, or nil when a kernel driver holds the interface.
  public let processID: Int32?
  /// The process name or the kernel driver class.
  public let name: String

  /// Creates an owner from a process ID, nil for a kernel driver, and the holder's name.
  public init(processID: Int32?, name: String) {
    self.processID = processID
    self.name = name
  }

  /// The user-facing sentence that names the holder and says OpenJoystickDriver serves the
  /// controller when the holder releases it.
  ///
  /// - Parameters:
  ///   - owner: The holder, or nil when the interface names none.
  ///   - localize: Returns the catalog text of a key.
  /// - Returns: The localized sentence.
  public static func heldMessage(
    for owner: Self?,
    localize: (String) -> String
  ) -> String {
    guard let owner else { return localize("status.controllerOwner.unnamed") }
    guard let pid = owner.processID else {
      return unsafe String(format: localize("status.controllerOwner.nameOnly"), owner.name)
    }
    return unsafe String(
      format: localize("status.controllerOwner.named"),
      owner.name,
      String(pid)
    )
  }

  /// The holder's name with its process ID, or the name alone for a kernel driver.
  ///
  /// - Parameter localize: Returns the catalog text of a key.
  /// - Returns: The localized label.
  public func label(localize: (String) -> String) -> String {
    guard let processID else { return name }
    return unsafe String(format: localize("ui.controllers.holder"), name, String(processID))
  }

  /// Parses a `UsbExclusiveOwner` or `IOUserClientCreator` registry value; nil for an empty
  /// value, which names no holder.
  public init?(registryValue: String) {
    let value = registryValue.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty else { return nil }
    let prefix = "pid "
    if value.hasPrefix(prefix), let comma = value.firstIndex(of: ","),
      let parsedID = Int32(value[value.index(value.startIndex, offsetBy: prefix.count)..<comma]),
      case let name = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces),
      !name.isEmpty
    {
      self.init(processID: parsedID, name: name)
    } else {
      self.init(processID: nil, name: value)
    }
  }
}
