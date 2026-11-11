public import IOKit
import IOKit.hid
public import OpenJoystickDriverKit

extension HIDElementDescription {
  /// The input elements of `elements`, in the order IOKit listed them.
  public static func inputs(of elements: [IOHIDElement]) -> [HIDElementDescription] {
    elements.filter { HIDDeviceStream.reportKind(for: $0) == .input }.enumerated().map {
      order,
      element in
      HIDElementDescription(
        usagePage: IOHIDElementGetUsagePage(element),
        usage: IOHIDElementGetUsage(element),
        cookie: IOHIDElementGetCookie(element),
        logicalMinimum: IOHIDElementGetLogicalMin(element),
        logicalMaximum: IOHIDElementGetLogicalMax(element),
        arrivalOrder: order
      )
    }
  }
}
