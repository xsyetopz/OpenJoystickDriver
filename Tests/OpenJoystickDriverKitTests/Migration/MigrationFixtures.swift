enum MigrationFixtures {
  static let alphaOne = "openjoystickdriver/v1alpha1"
  static let alphaTwo = "openjoystickdriver/v1alpha2"

  static func document(_ version: String, _ kind: String, _ rest: String) -> String {
    #"{"apiVersion": "\#(version)", "kind": "\#(kind)", \#(rest)}"#
  }

  /// The `AccessGrants.json` of the reporter in #59, who saw E5001 in the Access area.
  static let accessGrants = document(
    alphaOne,
    "AccessGrants",
    #""enabled": true, "grants": [], "tokens": [], "web": {"enabled": false}"#
  )

  /// A profile with a `doubleTap`, which `v1alpha3` writes as `multiTap`.
  static let profile = document(
    alphaOne,
    "Profile",
    #"""
    "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E", "name": "Tap",
    "device": {"vendorID": 1356, "productID": 3302},
    "applicationScope": {"type": "Global"},
    "outputPolicy": {"physicalInput": "Shared", "virtualGamepad": "Mapped"},
    "bindings": [{
      "id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D6A",
      "source": {"type": "Button", "button": "East"},
      "destination": {"type": "GamepadButton", "button": "South"},
      "doubleTap": {"windowMs": 250, "destination": {"type": "GamepadButton", "button": "North"}}
    }]
    """#
  )

  /// A user record of a controller the catalog does not bundle.
  static let userRecord = document(
    alphaOne,
    "Controller",
    #"""
    "vendorID": 4660, "productID": 43981,
    "modes": [{"id": "default", "protocol": {"family": "XboxGIP"}}]
    """#
  )

  /// A patch with bit-addressable fields to convert.
  static let patch = document(
    alphaOne,
    "ControllerPatch",
    #"""
    "selector": {"vendorID": 1356, "productID": 3302},
    "patch": {"input": {"report": {"length": {"atLeast": 2}},
      "buttons": [{"control": "South", "byte": 1, "mask": 12}],
      "axes": [{"control": "LeftStickX", "byte": 2, "bits": 16}]}}
    """#
  )

  /// A `v1alpha2` patch that deletes keys with `null`.
  static let nullPatch = document(
    alphaTwo,
    "ControllerPatch",
    #"""
    "selector": {"vendorID": 1, "productID": 2},
    "patch": {"usb": null, "tuning": {"replyTimeoutMs": null, "frameQueueCapacity": 8}}
    """#
  )
}
