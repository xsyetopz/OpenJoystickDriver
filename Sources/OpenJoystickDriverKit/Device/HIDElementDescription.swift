import Foundation

/// One input element of a HID device as the platform lists it: the facts SDL's element order
/// reads.
public struct HIDElementDescription: Codable, Equatable, Sendable {
  /// The HID usage page of the element.
  public let usagePage: UInt32
  /// The HID usage of the element.
  public let usage: UInt32
  /// The platform's cookie for the element; two elements with one cookie are one element.
  public let cookie: UInt32
  /// The least value the element reports.
  public let logicalMinimum: Int
  /// The greatest value the element reports.
  public let logicalMaximum: Int
  /// The position of the element in the platform's list, from 0.
  public let arrivalOrder: Int

  /// Creates an element from its fields.
  public init(
    usagePage: UInt32,
    usage: UInt32,
    cookie: UInt32,
    logicalMinimum: Int,
    logicalMaximum: Int,
    arrivalOrder: Int
  ) {
    self.usagePage = usagePage
    self.usage = usage
    self.cookie = cookie
    self.logicalMinimum = logicalMinimum
    self.logicalMaximum = logicalMaximum
    self.arrivalOrder = arrivalOrder
  }
}
