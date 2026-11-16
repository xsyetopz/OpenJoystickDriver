#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Lighting section: a toggle for the controller's default color and a color well.
  struct ProfileLightingEditor: View {
    /// The profile's color, or nil for the controller's default.
    let color: ControllerColor?
    /// Sets the color; nil restores the default.
    let onChange: (ControllerColor?) -> Void

    /// The lighting section.
    var body: some View {
      Section(header: Text(OJDLocalized.string("ui.inputTest.lighting"))) {
        Toggle(
          OJDLocalized.string("ui.profiles.useControllerDefaultColor"),
          isOn: Binding(
            get: { color == nil },
            set: { useDefault in
              onChange(useDefault ? nil : ControllerColor(red: 0, green: 122, blue: 255))
            }
          )
        ).help(OJDLocalized.string("ui.profiles.useDefaultColorHelp"))
        if color != nil {
          OJDLabeledRow(OJDLocalized.string("ui.inputTest.color")) {
            OJDPhysicalColorWell(color: colorBinding).frame(width: 44, height: 24)
              .ojdAccessibilityLabel(OJDLocalized.string("ui.inputTest.color"))
              .help(OJDLocalized.string("ui.profiles.lightingColorHelp"))
          }
        }
      }
    }

    /// The color well's binding; choosing a color sets the profile's color.
    private var colorBinding: Binding<NSColor> {
      Binding(
        get: {
          let value = color ?? ControllerColor(red: 0, green: 122, blue: 255)
          return NSColor(
            calibratedRed: CGFloat(value.red) / 255,
            green: CGFloat(value.green) / 255,
            blue: CGFloat(value.blue) / 255,
            alpha: 1
          )
        },
        set: { value in
          let converted = value.usingColorSpace(.deviceRGB) ?? value
          onChange(
            ControllerColor(
              red: UInt8((converted.redComponent * 255).rounded()),
              green: UInt8((converted.greenComponent * 255).rounded()),
              blue: UInt8((converted.blueComponent * 255).rounded())
            )
          )
        }
      )
    }
  }

#endif
