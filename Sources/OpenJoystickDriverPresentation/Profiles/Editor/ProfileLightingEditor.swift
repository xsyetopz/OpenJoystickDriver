#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileLightingEditor: View {
    let color: ControllerColor?
    let onChange: (ControllerColor?) -> Void

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            OJDLocalized.string(
              "profiles.useControllerDefaultColor"
            ),
            isOn: Binding(
              get: { color == nil },
              set: { useDefault in
                onChange(useDefault ? nil : ControllerColor(red: 0, green: 122, blue: 255))
              }
            )
          )
          if color != nil {
            HStack {
              Text(OJDLocalized.string("inputTest.color"))
              Spacer()
              OJDPhysicalColorWell(color: colorBinding).frame(width: 44, height: 24)
            }
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("inputTest.lighting"))
      }
    }

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
